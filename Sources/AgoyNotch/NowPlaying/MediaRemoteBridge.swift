//
//  MediaRemoteBridge.swift
//  AgoyNotch
//
//  ⚠️ PRIVATE FRAMEWORK BOUNDARY — READ THIS BEFORE EDITING ⚠️
//
//  This file is the ONLY place that touches Apple's PRIVATE MediaRemote framework. It
//  loads the framework at runtime with dlopen/dlsym and casts the resolved symbols to
//  C-function typealiases with `unsafeBitCast`. Consequences you must understand:
//
//    • NOT App Store eligible. Private frameworks are forbidden in the Mac App Store.
//      This app can only be distributed outside the store (notarized) or run locally.
//    • May need to run unsandboxed / locally signed. The sandbox blocks loading private
//      frameworks, so for local use build & run straight from Xcode (My Mac) or sign
//      ad-hoc.
//    • macOS 15.4+ entitlement enforcement. Since macOS 15.4 the `mediaremoted` daemon
//      verifies caller entitlements before returning Now Playing data. On the target
//      macOS 27 an unentitled build may therefore receive EMPTY info even though a symbol
//      resolved fine. Everything here is written to DEGRADE GRACEFULLY to "Nothing
//      playing" in that case — missing symbols and empty results are both tolerated.
//    • Fully local. No network, no telemetry — this bridge only talks to the local media
//      daemon.
//
//  (Content rephrased for compliance with licensing restrictions.)
//

import Foundation

/// Well-known MediaRemote command integers passed to `MRMediaRemoteSendCommand`.
///
/// The MVP uses toggle / next / previous. The others are listed for the roadmap. These
/// integer values are the long-documented MediaRemote command codes.
enum MRCommand: Int {
    case play           = 0
    case pause          = 1
    case togglePlayPause = 2
    case stop           = 3
    case next           = 4
    case previous       = 5
}

/// Isolated wrapper around the private MediaRemote framework.
///
/// Construct it with `MediaRemoteBridge()`. If the framework or any required symbol
/// cannot be resolved, the initializer still succeeds but the corresponding calls become
/// no-ops / return empty — callers never have to handle a failed load specially.
final class MediaRemoteBridge {

    // MARK: - C function typealiases (every one is @convention(c))

    /// `MRMediaRemoteGetNowPlayingInfo(queue, completion)` — completion receives the
    /// Now Playing info dictionary (keyed by the `Keys` string constants below).
    typealias GetNowPlayingInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void

    /// `MRMediaRemoteRegisterForNowPlayingNotifications(queue)` — begins delivering the
    /// `kMRMediaRemoteNowPlayingInfoDidChangeNotification` NotificationCenter posts.
    typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

    /// `MRMediaRemoteUnregisterForNowPlayingNotifications()` — stops the above.
    typealias UnregisterFn = @convention(c) () -> Void

    /// `MRMediaRemoteSendCommand(command, userInfo) -> Bool` — sends a transport command.
    typealias SendCommandFn = @convention(c) (Int, [AnyHashable: Any]?) -> Bool

    /// `MRMediaRemoteGetNowPlayingApplicationIsPlaying(queue, completion)` — completion
    /// receives the current play/pause state as a Bool.
    typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void

    // MARK: - Resolved function pointers (nil when unavailable)

    private let getNowPlayingInfo: GetNowPlayingInfoFn?
    private let registerForNotifications: RegisterFn?
    private let unregisterForNotifications: UnregisterFn?
    private let sendCommand: SendCommandFn?
    private let getIsPlaying: GetIsPlayingFn?

    /// The dlopen handle, held for the lifetime of the bridge. Intentionally never
    /// dlclose'd — the framework stays loaded for the whole app run.
    private let handle: UnsafeMutableRawPointer?

    // MARK: - Info-dictionary keys
    //
    // These are STRING keys into the Now Playing info dictionary, not exported symbols,
    // so they are hard-coded (each key's string value equals its name). They are grouped
    // in a namespace so callers reference `MediaRemoteBridge.Keys.title`, etc.
    enum Keys {
        static let title        = "kMRMediaRemoteNowPlayingInfoTitle"
        static let artist       = "kMRMediaRemoteNowPlayingInfoArtist"
        static let album        = "kMRMediaRemoteNowPlayingInfoAlbum"
        static let artworkData  = "kMRMediaRemoteNowPlayingInfoArtworkData"
        static let playbackRate = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    }

    /// NotificationCenter name posted when Now Playing info changes.
    static let infoDidChangeNotification =
        Notification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification")

    /// NotificationCenter name posted when the playing/paused state changes.
    static let isPlayingDidChangeNotification =
        Notification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification")

    // MARK: - Init

    init() {
        // Load the private framework. If it fails, all function pointers stay nil and the
        // whole bridge becomes a safe no-op.
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        let handle = dlopen(path, RTLD_NOW)
        self.handle = handle

        // Helper that resolves a symbol and casts it to the requested C-function type,
        // returning nil if either the framework or the symbol is unavailable.
        func load<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let sym = dlsym(handle, name) else { return nil }
            return unsafeBitCast(sym, to: type)
        }

        self.getNowPlayingInfo =
            load("MRMediaRemoteGetNowPlayingInfo", as: GetNowPlayingInfoFn.self)
        self.registerForNotifications =
            load("MRMediaRemoteRegisterForNowPlayingNotifications", as: RegisterFn.self)
        self.unregisterForNotifications =
            load("MRMediaRemoteUnregisterForNowPlayingNotifications", as: UnregisterFn.self)
        self.sendCommand =
            load("MRMediaRemoteSendCommand", as: SendCommandFn.self)
        self.getIsPlaying =
            load("MRMediaRemoteGetNowPlayingApplicationIsPlaying", as: GetIsPlayingFn.self)
    }

    // MARK: - Public API (all safe no-ops when the symbol is missing)

    /// True when at least the "get info" symbol resolved, i.e. the framework is usable.
    var isAvailable: Bool { getNowPlayingInfo != nil }

    /// Fetch the current Now Playing info dictionary. The completion runs on `queue`.
    /// If the symbol is missing the completion is never called with real data — callers
    /// treat the absence as "nothing playing".
    func fetchNowPlayingInfo(on queue: DispatchQueue = .main,
                             completion: @escaping ([String: Any]) -> Void) {
        guard let getNowPlayingInfo else {
            completion([:])
            return
        }
        getNowPlayingInfo(queue, completion)
    }

    /// Fetch the current play/pause state. No-op (returns false) when unavailable.
    func fetchIsPlaying(on queue: DispatchQueue = .main,
                        completion: @escaping (Bool) -> Void) {
        guard let getIsPlaying else {
            completion(false)
            return
        }
        getIsPlaying(queue, completion)
    }

    /// Begin receiving Now Playing change notifications on the given queue.
    func registerForNotifications(on queue: DispatchQueue = .main) {
        registerForNotifications?(queue)
    }

    /// Stop receiving Now Playing change notifications.
    func unregister() {
        unregisterForNotifications?()
    }

    /// Send a transport command. Returns false when the symbol is unavailable.
    @discardableResult
    func send(_ command: MRCommand) -> Bool {
        guard let sendCommand else { return false }
        return sendCommand(command.rawValue, nil)
    }
}
