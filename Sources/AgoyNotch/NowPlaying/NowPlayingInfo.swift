//
//  NowPlayingInfo.swift
//  AgoyNotch
//
//  Plain, UI-agnostic data model describing the current Now Playing state.
//  Populated by NowPlayingManager from the Now Playing helper (any app) or the Apple Music
//  AppleScript fallback, and consumed by the SwiftUI views. Everything here is local-only —
//  no network, no telemetry.
//

import AppKit

/// Where a `NowPlayingInfo` came from.
enum NowPlayingSource: Equatable, Sendable {
    case none
    case mediaRemote
    case appleMusicScript
}

/// A snapshot of the system's current Now Playing media.
///
/// `NSImage` is not `Equatable`, so `Equatable` is implemented by hand. Artwork is compared
/// by `artworkKey` (a hash over the image bytes) plus nil-ness, never by re-encoding it.
/// `@unchecked Sendable`: the NSImage is never mutated after creation.
struct NowPlayingInfo: Equatable, @unchecked Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: NSImage?
    var isPlaying: Bool
    var source: NowPlayingSource = .none
    /// Bundle ID of the app playing (for its icon), e.g. com.google.Chrome.
    var sourceBundleID: String? = nil
    var artworkKey: Int? = nil

    /// The empty / "nothing is playing" state.
    static let empty = NowPlayingInfo(
        title: nil,
        artist: nil,
        album: nil,
        artwork: nil,
        isPlaying: false
    )

    /// Title to show in the UI, with a friendly placeholder when nothing is playing.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return "Nothing playing"
    }

    /// Artist to show in the UI; empty string when unknown so layouts can hide it.
    var displayArtist: String {
        if let artist, !artist.isEmpty { return artist }
        return ""
    }

    /// True when there is any real media to display (used to decide whether the
    /// collapsed pill shows a now-playing hint at all).
    var hasMedia: Bool {
        (title?.isEmpty == false) || (artist?.isEmpty == false) || artwork != nil
    }

    static func == (lhs: NowPlayingInfo, rhs: NowPlayingInfo) -> Bool {
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.source == rhs.source &&
        lhs.sourceBundleID == rhs.sourceBundleID &&
        lhs.artworkKey == rhs.artworkKey &&
        (lhs.artwork == nil) == (rhs.artwork == nil)
    }
}
