//
//  NowPlayingManager.swift
//  AgoyNotch
//
//  Observable service that turns the raw MediaRemote info dictionary into a published
//  `NowPlayingInfo` and exposes transport commands. All MediaRemote unsafety lives in
//  `MediaRemoteBridge`; this layer is pure, testable glue.
//
//  Local-only: this talks solely to the on-device media daemon. No network, no telemetry.
//
//  Concurrency / isolation
//  ------------------------
//  This type is `@MainActor`-isolated. It is a UI-facing `ObservableObject` whose
//  `@Published info` drives SwiftUI, so every mutation of `info` must happen on the main
//  actor anyway. Making the whole class main-actor-isolated states that invariant to the
//  compiler, so under Swift 6 strict concurrency (which tools-version 6.0 can enforce even
//  under language mode v5) the data-race diagnostics disappear WITHOUT leaning on the
//  language-mode setting:
//
//    • The MediaRemote fetch completion is delivered on an arbitrary background queue, so
//      it must NOT touch `self` directly. We parse the dictionary into a pure
//      `NowPlayingInfo` value first (no `self`), then hop to the main actor exactly once
//      via `Task { @MainActor in … }` to assign `info`. `self` is captured weakly and the
//      mutation is main-actor-isolated, so there is no "Sending 'self' risks a data race".
//    • NotificationCenter observer blocks are `@Sendable`. We therefore capture nothing
//      non-Sendable in them: each block hops to the main actor and calls `refresh()` there.
//    • The follow-up refresh delay also hops to the main actor before touching `self`.
//

import AppKit
import Combine

/// Fetches and publishes the system Now Playing state and forwards transport commands.
///
/// Main-actor-isolated: its `@Published info` feeds SwiftUI, and all call sites
/// (`AppDelegate` launch/terminate delegate methods, `NotchViewModel`, `NotchView`
/// transport buttons) already run on the main actor.
@MainActor
final class NowPlayingManager: ObservableObject {

    /// The latest Now Playing snapshot. Starts empty and updates on the main actor.
    @Published private(set) var info: NowPlayingInfo = .empty

    private let bridge = MediaRemoteBridge()
    private var notificationObservers: [NSObjectProtocol] = []

    /// Background queue used for the MediaRemote fetch callbacks so we never block the UI.
    private let workQueue = DispatchQueue(label: "com.agoynotch.nowplaying", qos: .userInitiated)

    // MARK: - Lifecycle

    /// Begin observing Now Playing changes and do an initial refresh.
    func start() {
        // Register for the daemon's change notifications (delivered on the main queue),
        // then observe them via NotificationCenter.
        bridge.registerForNotifications(on: .main)

        let center = NotificationCenter.default

        // The observer block is `@Sendable`; capture only a weak `self` (Sendable) and hop
        // to the main actor before calling the main-actor-isolated `refresh()`. We do NOT
        // capture a non-Sendable local closure here, which is what previously tripped the
        // "non-Sendable capture in a @Sendable closure" warning.
        let observe: (Notification.Name) -> NSObjectProtocol = { [weak self] name in
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in self?.refresh() }
            }
        }

        notificationObservers.append(observe(MediaRemoteBridge.infoDidChangeNotification))
        notificationObservers.append(observe(MediaRemoteBridge.isPlayingDidChangeNotification))

        refresh()
    }

    /// Stop observing and unregister from the daemon.
    func stop() {
        let center = NotificationCenter.default
        notificationObservers.forEach { center.removeObserver($0) }
        notificationObservers.removeAll()
        bridge.unregister()
    }

    deinit {
        // Under Swift's isolated synchronous `deinit` (SE-0371, standard in the Xcode 27
        // toolchain), a global-actor-isolated class gets a main-actor-isolated `deinit`,
        // so it may touch the main-actor-isolated, non-Sendable `notificationObservers` /
        // `bridge` and call `stop()` directly — the runtime hops to the main actor first.
        stop()
    }

    // MARK: - Refresh

    /// Pull the latest info dictionary and republish `info` on the main actor.
    func refresh() {
        // Fetch the info dict on a background queue so artwork decoding stays off main.
        // The completion runs on `workQueue`, so it must not touch `self` directly: parse
        // the dictionary into a pure value first, then hop to the main actor once to assign.
        bridge.fetchNowPlayingInfo(on: workQueue) { [weak self] dict in
            // Empty dict → nothing playing (also the macOS 15.4+ entitlement fallback).
            guard !dict.isEmpty else {
                Task { @MainActor in self?.info = .empty }
                return
            }

            let title  = dict[MediaRemoteBridge.Keys.title] as? String
            let artist = dict[MediaRemoteBridge.Keys.artist] as? String
            let album  = dict[MediaRemoteBridge.Keys.album] as? String

            var artwork: NSImage?
            if let data = dict[MediaRemoteBridge.Keys.artworkData] as? Data {
                artwork = NSImage(data: data)
            }

            // PlaybackRate > 0 means actively playing. The value may come back as any
            // NSNumber-ish type, so coerce defensively.
            let rate = (dict[MediaRemoteBridge.Keys.playbackRate] as? NSNumber)?.doubleValue ?? 0
            let isPlaying = rate > 0

            let snapshot = NowPlayingInfo(
                title: title,
                artist: artist,
                album: album,
                artwork: artwork,
                isPlaying: isPlaying
            )

            // Hop to the main actor exactly once to publish the parsed snapshot.
            Task { @MainActor in self?.info = snapshot }
        }
    }

    // MARK: - Transport commands

    /// Toggle play/pause of whatever currently holds the Now Playing session.
    func togglePlayPause() {
        bridge.send(.togglePlayPause)
        // Optimistically re-read shortly after so the icon reflects the new state even if
        // a change notification is slow to arrive.
        scheduleFollowUpRefresh()
    }

    /// Skip to the next track.
    func next() {
        bridge.send(.next)
        scheduleFollowUpRefresh()
    }

    /// Skip to the previous track.
    func previous() {
        bridge.send(.previous)
        scheduleFollowUpRefresh()
    }

    private func scheduleFollowUpRefresh() {
        // Main-actor-safe delay: the task body runs on the main actor, so touching `self`
        // (and calling the main-actor-isolated `refresh()`) is race-free. `self` is weak so
        // a pending follow-up never keeps the manager alive.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            self?.refresh()
        }
    }
}
