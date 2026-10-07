//
//  NowPlayingManager.swift
//  MacNotch
//
//  Observable service that turns the raw MediaRemote info dictionary into a published
//  `NowPlayingInfo` and exposes transport commands. All MediaRemote unsafety lives in
//  `MediaRemoteBridge`; this layer is pure, testable glue.
//
//  Local-only: this talks solely to the on-device media daemon. No network, no telemetry.
//

import AppKit
import Combine

/// Fetches and publishes the system Now Playing state and forwards transport commands.
final class NowPlayingManager: ObservableObject {

    /// The latest Now Playing snapshot. Starts empty and updates on the main thread.
    @Published private(set) var info: NowPlayingInfo = .empty

    private let bridge = MediaRemoteBridge()
    private var notificationObservers: [NSObjectProtocol] = []

    /// Background queue used for the MediaRemote fetch callbacks so we never block the UI.
    private let workQueue = DispatchQueue(label: "com.macnotch.nowplaying", qos: .userInitiated)

    // MARK: - Lifecycle

    /// Begin observing Now Playing changes and do an initial refresh.
    func start() {
        // Register for the daemon's change notifications (delivered on the main queue),
        // then observe them via NotificationCenter.
        bridge.registerForNotifications(on: .main)

        let center = NotificationCenter.default
        let handler: (Notification) -> Void = { [weak self] _ in self?.refresh() }

        notificationObservers.append(
            center.addObserver(forName: MediaRemoteBridge.infoDidChangeNotification,
                               object: nil, queue: .main) { note in handler(note) }
        )
        notificationObservers.append(
            center.addObserver(forName: MediaRemoteBridge.isPlayingDidChangeNotification,
                               object: nil, queue: .main) { note in handler(note) }
        )

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
        stop()
    }

    // MARK: - Refresh

    /// Pull the latest info dictionary and republish `info` on the main thread.
    func refresh() {
        // Fetch the info dict on a background queue so artwork decoding stays off main.
        bridge.fetchNowPlayingInfo(on: workQueue) { [weak self] dict in
            guard let self else { return }

            // Empty dict → nothing playing (also the macOS 15.4+ entitlement fallback).
            guard !dict.isEmpty else {
                DispatchQueue.main.async { self.info = .empty }
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

            DispatchQueue.main.async { self.info = snapshot }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }
}
