//
//  AdapterStream.swift
//  AgoyNotch
//
//  Pure, Foundation-only pieces of the Now Playing helper integration (the vendored
//  ungive/mediaremote-adapter, run as `/usr/bin/perl mediaremote-adapter.pl … stream`):
//  line splitting, JSON message decoding, diff merging, the snapshot model, the source
//  precedence rule, the restart policy and the argument lists. No AppKit, no app types, so
//  the Linux self-test harness can compile this file on its own.
//

import Foundation

/// Splits the helper's stdout byte stream into complete, non-empty `\n`-terminated lines.
struct AdapterLineBuffer {
    let maxBytes: Int
    private var pending = Data()
    /// Set once a line longer than `maxBytes` was dropped.
    private(set) var didOverflow = false

    init(maxBytes: Int = 16 * 1024 * 1024) {
        self.maxBytes = maxBytes
    }

    mutating func append(_ chunk: Data) -> [Data] {
        pending.append(chunk)
        var lines: [Data] = []
        while let nl = pending[pending.startIndex...].firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<nl]
            if !line.isEmpty { lines.append(Data(line)) }
            pending = Data(pending[pending.index(after: nl)...])
        }
        if pending.count > maxBytes {
            pending = Data()
            didOverflow = true
        }
        return lines
    }
}

/// One `{"type":"data","diff":<bool>,"payload":{…}}` line from the helper.
struct AdapterStreamMessage {
    let diff: Bool
    let payload: [String: Any]

    static func decode(_ line: Data) -> AdapterStreamMessage? {
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any]
        else { return nil }
        return AdapterStreamMessage(diff: object["diff"] as? Bool ?? false, payload: payload)
    }
}

/// The media the helper reports, reduced to what the UI shows.
struct AdapterSnapshot: Equatable, Sendable {
    let title: String
    let artist: String?
    let album: String?
    let sourceBundleID: String?
    let artworkBase64: String?
    let isPlaying: Bool
}

/// Merges stream messages into the current payload and derives a snapshot from it.
enum AdapterState {
    static func apply(_ m: AdapterStreamMessage, to state: [String: Any]) -> [String: Any] {
        if !m.diff {
            return m.payload.filter { !($0.value is NSNull) }
        }
        var next = state
        for (key, value) in m.payload {
            if value is NSNull {
                next[key] = nil
            } else {
                next[key] = value
            }
        }
        return next
    }

    static func snapshot(from state: [String: Any]) -> AdapterSnapshot? {
        guard let title = state["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        func nonEmpty(_ key: String) -> String? {
            guard let s = state[key] as? String, !s.isEmpty else { return nil }
            return s
        }
        return AdapterSnapshot(
            title: title,
            artist: nonEmpty("artist"),
            album: nonEmpty("album"),
            sourceBundleID: nonEmpty("parentApplicationBundleIdentifier") ?? nonEmpty("bundleIdentifier"),
            artworkBase64: nonEmpty("artworkData"),
            isPlaying: state["playing"] as? Bool ?? false
        )
    }
}

/// Which source the panel shows when both the helper and the AppleScript poll have data.
enum NowPlayingSourceChoice: Equatable {
    case adapter, appleScript

    static func choose(adapterHasMedia: Bool, adapterPlaying: Bool,
                       scriptHasMedia: Bool, scriptPlaying: Bool) -> NowPlayingSourceChoice {
        if adapterPlaying { return .adapter }
        if scriptPlaying { return .appleScript }
        if adapterHasMedia { return .adapter }
        return .appleScript
    }
}

/// Command IDs from `MediaRemoteAdapter.h` (`kMRATogglePlayPause` etc.).
enum AdapterCommand: Int, Sendable {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

/// Helper state, shown in Settings.
enum AdapterStatus: Equatable, Sendable {
    case notBundled
    case starting
    case running
    case failed(String)
}

/// At most `maxRestarts` automatic restarts inside a sliding `window`.
struct AdapterRestartPolicy {
    let window: TimeInterval = 60
    let maxRestarts = 3
    private var restarts: [Date] = []

    mutating func allowRestart(at now: Date) -> Bool {
        restarts.removeAll { now.timeIntervalSince($0) > window }
        guard restarts.count < maxRestarts else { return false }
        restarts.append(now)
        return true
    }
}

/// Argument arrays for `/usr/bin/perl` (no shell involved).
enum AdapterArguments {
    static func stream(script: String, framework: String) -> [String] {
        [script, framework, "stream", "--debounce=100"]
    }

    static func send(script: String, framework: String, _ c: AdapterCommand) -> [String] {
        [script, framework, "send", String(c.rawValue)]
    }
}

/// Artwork identity over every byte (`Data.hashValue` only covers the first 80 bytes).
/// Per-process seeded; compared only within one launch.
enum ArtworkKey {
    static func of(_ data: Data) -> Int {
        var h = Hasher()
        data.withUnsafeBytes { h.combine(bytes: $0) }
        return h.finalize()
    }
}

/// The only way externally sourced text (stderr, JSON) is logged: `%@` avoids format-string
/// injection from `%` in that text.
enum AgoyLog {
    static func write(_ s: String) {
        NSLog("%@", NSString(string: "[AgoyNotch] " + s))
    }
}
