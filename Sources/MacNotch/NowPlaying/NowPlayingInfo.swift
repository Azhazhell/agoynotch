//
//  NowPlayingInfo.swift
//  MacNotch
//
//  Plain, UI-agnostic data model describing the current Now Playing state.
//  Populated by NowPlayingManager from the private MediaRemote framework and
//  consumed by the SwiftUI views. Everything here is local-only — no network,
//  no telemetry.
//

import AppKit

/// A snapshot of the system's current Now Playing media.
///
/// `NSImage` is not `Equatable`, so `Equatable` is implemented by hand. Artwork is
/// intentionally compared by its backing data (TIFF representation) rather than by
/// reference, so that two decodes of the same bytes compare equal and SwiftUI does
/// not needlessly re-render. Comparing full TIFF data on every change is cheap
/// relative to how rarely Now Playing info changes.
struct NowPlayingInfo: Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: NSImage?
    var isPlaying: Bool

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
        lhs.artwork?.tiffRepresentation == rhs.artwork?.tiffRepresentation
    }
}
