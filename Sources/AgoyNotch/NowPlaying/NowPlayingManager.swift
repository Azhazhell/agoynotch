//
//  NowPlayingManager.swift
//  AgoyNotch
//
//  Observable service that polls the current Apple Music state (via AppleScript) into a
//  published `NowPlayingInfo` and exposes transport commands.
//
//  DATA SOURCE: the LIVE source is `AppleScriptNowPlaying` (Apple Music only). The private
//  MediaRemote path (`MediaRemoteBridge`) is kept in the tree as a DORMANT historical
//  fallback — it is no longer the live path because macOS 15.4+ denies Now Playing data to
//  unentitled callers (see AppleScriptNowPlaying / README). The public API below
//  (`info`, `start`/`stop`, `togglePlayPause`/`next`/`previous`) is UNCHANGED so
//  NotchView / NotchViewModel keep working as-is.
//
//  Local-only: this talks solely to the on-device Music.app via AppleScript. No network,
//  no telemetry. Apple Music artwork is read as raw local bytes; nothing is fetched over
//  the network.
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
//    • Polling runs NSAppleScript synchronously on a background queue (artwork decoding is
//      done there too, off the main thread). The background block must NOT touch `self`
//      directly: it builds a pure `NowPlayingInfo` value via the Sendable
//      `AppleScriptNowPlaying`, then hops to the main actor exactly once via
//      `Task { @MainActor in … }` to assign `info`. `self` is captured weakly and the
//      mutation is main-actor-isolated, so there is no "Sending 'self' risks a data race".
//    • The follow-up refresh delay also hops to the main actor before touching `self`.
//

import AppKit
import Combine

/// Fetches and publishes the Apple Music Now Playing state and forwards transport commands.
///
/// Main-actor-isolated: its `@Published info` feeds SwiftUI, and all call sites
/// (`AppDelegate` launch/terminate delegate methods, `NotchViewModel`, `NotchView`
/// transport buttons) already run on the main actor.
@MainActor
final class NowPlayingManager: ObservableObject {

    /// The latest Now Playing snapshot. Starts empty and updates on the main actor.
    @Published private(set) var info: NowPlayingInfo = .empty

    /// LIVE data source: AppleScript to Apple Music. `MediaRemoteBridge` is intentionally
    /// NOT instantiated here anymore — it is dormant historical code (see file header /
    /// README). The provider is a pure, Sendable value we can call from a background queue.
    private let provider = AppleScriptNowPlaying()

    /// Background queue used to run the (synchronous) AppleScript polling + artwork decode
    /// so we never block the UI. Serial so overlapping polls can't pile up.
    private let workQueue = DispatchQueue(label: "com.agoynotch.nowplaying", qos: .userInitiated)

    /// Polling interval. AppleScript to Music is cheap enough to poll a couple times a
    /// second; ~1.5s keeps the panel responsive without hammering Music.app.
    private let pollInterval: TimeInterval = 1.5

    /// Repeating poll timer. A `DispatchSourceTimer` fires on `workQueue`, so its handler is
    /// already off the main thread (where AppleScript must run). Torn down in `stop()`.
    private var pollTimer: DispatchSourceTimer?

    // MARK: - Lifecycle

    /// Begin polling Apple Music and publish an initial snapshot immediately.
    func start() {
        // Immediate first read so the panel isn't blank until the first tick.
        refresh()

        // Repeating timer on the background work queue. The handler captures only a weak
        // `self` (Sendable) and the Sendable `provider`; it builds a pure snapshot, then
        // hops to the main actor once to publish — no non-Sendable capture, no data race.
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self, provider] in
            let snapshot = provider.fetchSnapshot()
            Task { @MainActor in self?.info = snapshot }
        }
        timer.resume()
        pollTimer = timer
    }

    /// Stop polling.
    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
    }

    deinit {
        // `deinit` is a *nonisolated synchronous* context, so it cannot read the
        // @MainActor-isolated `pollTimer` property to cancel it here. A `DispatchSourceTimer`
        // is automatically cancelled/released when its last reference drops, so letting the
        // stored timer deallocate is sufficient; `stop()` is the explicit teardown path and
        // AppDelegate calls it on `applicationWillTerminate`.
    }

    // MARK: - Refresh

    /// Pull the latest Apple Music snapshot and republish `info` on the main actor.
    func refresh() {
        // Run the (synchronous) AppleScript + artwork decode on the background queue so the
        // UI never blocks. The block must not touch `self` directly: build a pure value via
        // the Sendable provider, then hop to the main actor once to assign.
        workQueue.async { [weak self, provider] in
            let snapshot = provider.fetchSnapshot()
            Task { @MainActor in self?.info = snapshot }
        }
    }

    // MARK: - Transport commands

    /// Toggle play/pause of Apple Music.
    func togglePlayPause() {
        sendCommand { $0.togglePlayPause() }
    }

    /// Skip to the next track in Apple Music.
    func next() {
        sendCommand { $0.next() }
    }

    /// Skip to the previous track in Apple Music.
    func previous() {
        sendCommand { $0.previous() }
    }

    /// Runs a transport command on the background queue (AppleScript must stay off main),
    /// then schedules an optimistic re-read so the icon reflects the new state quickly.
    private func sendCommand(_ body: @escaping @Sendable (AppleScriptNowPlaying) -> Void) {
        workQueue.async { [provider] in
            body(provider)
        }
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
