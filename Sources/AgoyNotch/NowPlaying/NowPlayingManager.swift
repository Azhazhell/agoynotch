//
//  NowPlayingManager.swift
//  AgoyNotch
//
//  Observable service that publishes the current Now Playing state of any app into a
//  `NowPlayingInfo` and exposes transport commands.
//
//  DATA SOURCES (merged by the pure `NowPlayingSourceChoice.choose` rule):
//    • the vendored mediaremote-adapter helper (`MediaRemoteAdapterClient`), a
//      `/usr/bin/perl` child that streams Now Playing from every app — Apple Music,
//      Spotify, Apple TV and browser players (YouTube, SoundCloud, …);
//    • the Apple Music AppleScript poll (`AppleScriptNowPlaying`), which always runs so
//      Apple Music keeps working when the helper is not bundled or fails.
//  The public API (`info`, `start`/`stop`, `togglePlayPause`/`next`/`previous`) is
//  unchanged; `adapterStatus` is new and shown in Settings.
//
//  Local-only: the helper reads the on-device MediaRemote state and AppleScript talks to
//  the on-device Music.app. No network, no telemetry.
//
//  Concurrency / isolation
//  ------------------------
//  This type is `@MainActor`-isolated: `info` and `adapterStatus` drive SwiftUI.
//    • AppleScript polling runs on the background `workQueue`; it builds a pure
//      `NowPlayingInfo` and hops to the main actor once via `Task { @MainActor in … }`.
//    • The helper client calls back on its own serial queue; artwork is decoded there
//      (`ArtworkCache`), then the value hops to the main actor the same way.
//    • `republish()` is the single writer of `info`.
//

import AppKit
import Combine

/// Fetches and publishes the Now Playing state and forwards transport commands.
@MainActor
final class NowPlayingManager: ObservableObject {

    /// The latest Now Playing snapshot. Starts empty and updates on the main actor.
    @Published private(set) var info: NowPlayingInfo = .empty

    /// State of the all-apps helper, shown in Settings.
    @Published private(set) var adapterStatus: AdapterStatus = .starting

    /// Apple Music fallback source: a pure, Sendable value callable from a background queue.
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

    /// The all-apps helper; nil when not bundled or not startable.
    private var adapter: MediaRemoteAdapterClient?
    /// Latest value from each source; `republish()` picks one.
    private var adapterInfo: NowPlayingInfo?
    private var scriptInfo = NowPlayingInfo.empty

    // MARK: - Lifecycle

    /// Start the helper stream and the Apple Music poll, publishing an initial snapshot.
    func start() {
        startAdapter()

        // Immediate first read so the panel isn't blank until the first tick.
        refresh()

        // Repeating timer on the background work queue. The handler captures only a weak
        // `self` (Sendable) and the Sendable `provider`; it builds a pure snapshot, then
        // hops to the main actor once to publish — no non-Sendable capture, no data race.
        let timer = DispatchSource.makeTimerSource(queue: workQueue)
        timer.schedule(deadline: .now() + pollInterval, repeating: pollInterval)
        timer.setEventHandler { [weak self, provider] in
            let snapshot = provider.fetchSnapshot()
            Task { @MainActor in self?.scriptDidUpdate(snapshot) }
        }
        timer.resume()
        pollTimer = timer
    }

    /// Stop polling and stop the helper (synchronously signals the child).
    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        adapter?.stop()
        adapter = nil
    }

    deinit {
        // `deinit` is a *nonisolated synchronous* context, so it cannot read the
        // @MainActor-isolated `pollTimer` property to cancel it here. A `DispatchSourceTimer`
        // is automatically cancelled/released when its last reference drops, so letting the
        // stored timer deallocate is sufficient; `stop()` is the explicit teardown path and
        // AppDelegate calls it on `applicationWillTerminate`.
    }

    // MARK: - Helper

    private func startAdapter() {
        let paths: MediaRemoteAdapterClient.Paths
        do {
            paths = try MediaRemoteAdapterClient.bundledPaths()
        } catch MediaRemoteAdapterClient.SetupError.perlMissing {
            adapterStatus = .failed("/usr/bin/perl not found")
            AgoyLog.write("Now Playing helper unavailable: /usr/bin/perl not found; Apple Music only")
            return
        } catch {
            adapterStatus = .notBundled
            AgoyLog.write("Now Playing helper not bundled; Apple Music only")
            return
        }

        let cache = ArtworkCache()
        let client = MediaRemoteAdapterClient(
            paths: paths,
            onSnapshot: { [weak self, cache] snap in
                let info = snap.map { cache.info(for: $0) }
                Task { @MainActor in self?.adapterDidUpdate(info) }
            },
            onStatus: { [weak self] s in
                Task { @MainActor in self?.adapterStatus = s }
            }
        )
        adapter = client
        client.start()
    }

    private func adapterDidUpdate(_ value: NowPlayingInfo?) {
        adapterInfo = value
        republish()
    }

    private func scriptDidUpdate(_ value: NowPlayingInfo) {
        scriptInfo = value
        republish()
    }

    /// The single writer of `info`.
    private func republish() {
        let choice = NowPlayingSourceChoice.choose(
            adapterHasMedia: adapterInfo?.hasMedia ?? false,
            adapterPlaying: adapterInfo?.isPlaying ?? false,
            scriptHasMedia: scriptInfo.hasMedia,
            scriptPlaying: scriptInfo.isPlaying
        )
        let next = (choice == .adapter ? adapterInfo : nil) ?? scriptInfo
        if next != info { info = next }
    }

    // MARK: - Refresh

    /// Pull the latest Apple Music snapshot and republish on the main actor.
    func refresh() {
        // Run the (synchronous) AppleScript + artwork decode on the background queue so the
        // UI never blocks. The block must not touch `self` directly: build a pure value via
        // the Sendable provider, then hop to the main actor once to assign.
        workQueue.async { [weak self, provider] in
            let snapshot = provider.fetchSnapshot()
            Task { @MainActor in self?.scriptDidUpdate(snapshot) }
        }
    }

    // MARK: - Transport commands

    /// Toggle play/pause of the app being shown.
    func togglePlayPause() {
        if info.source == .mediaRemote, let adapter {
            adapter.send(.togglePlayPause)
            return
        }
        sendCommand { $0.togglePlayPause() }
    }

    /// Skip to the next track in the app being shown.
    func next() {
        if info.source == .mediaRemote, let adapter {
            adapter.send(.nextTrack)
            return
        }
        sendCommand { $0.next() }
    }

    /// Skip to the previous track in the app being shown.
    func previous() {
        if info.source == .mediaRemote, let adapter {
            adapter.send(.previousTrack)
            return
        }
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

/// Turns helper snapshots into `NowPlayingInfo`, decoding artwork only when it changes.
/// Used ONLY from the helper client's serial callback queue (hence `@unchecked Sendable`).
private final class ArtworkCache: @unchecked Sendable {
    private var lastBase64: String?
    private var lastImage: NSImage?
    private var lastKey: Int?

    func info(for s: AdapterSnapshot) -> NowPlayingInfo {
        if s.artworkBase64 != lastBase64 {
            lastBase64 = s.artworkBase64
            lastImage = nil
            lastKey = nil
            if let b64 = s.artworkBase64,
               let data = Data(base64Encoded: b64),
               let image = NSImage(data: data) {
                lastImage = image
                lastKey = ArtworkKey.of(data)
            } else if s.artworkBase64 != nil {
                #if DEBUG
                print("[AgoyNotch] Now Playing artwork could not be decoded")
                #endif
            }
        }
        return NowPlayingInfo(
            title: s.title,
            artist: s.artist,
            album: s.album,
            artwork: lastImage,
            isPlaying: s.isPlaying,
            source: .mediaRemote,
            sourceBundleID: s.sourceBundleID,
            artworkKey: lastKey
        )
    }
}
