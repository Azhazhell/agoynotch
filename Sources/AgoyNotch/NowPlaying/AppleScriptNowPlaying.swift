//
//  AppleScriptNowPlaying.swift
//  AgoyNotch
//
//  AppleScript-based Now Playing provider for Apple Music (Music.app).
//
//  ROLE: the Apple Music FALLBACK. Now Playing from every app (Music, Spotify, TV,
//  browsers) comes from the vendored mediaremote-adapter helper (MediaRemoteAdapterClient),
//  because since macOS 15.4 apps cannot read MediaRemote directly. This poll always runs
//  too, so Apple Music keeps working when the helper is missing or fails; NowPlayingManager
//  picks which source is shown (NowPlayingSourceChoice).
//
//  SCOPE: Apple Music ONLY. We read Music.app's player state + current track and send its
//  transport commands. No other player is contacted.
//
//  THREADING: `fetchSnapshot()` runs NSAppleScript synchronously and MUST be called off the
//  main thread (NowPlayingManager calls it on a background queue). Artwork is decoded there
//  too, so no image work touches the main actor. The parsed value (`NowPlayingInfo`) is a
//  plain Sendable-friendly snapshot the caller publishes on the main actor.
//
//  PERMISSIONS: the first AppleScript send to Music triggers a macOS Automation consent
//  prompt (System Settings → Privacy & Security → Automation). As an unbundled SPM
//  executable the prompt can be flaky; every call degrades gracefully — if Music is not
//  running, or AppleScript returns an authorization error (-1743) or any other error, we
//  return `.empty` ("Nothing playing") and log a concise message instead of crashing.
//
//  LOCAL-ONLY: no network. Apple Music artwork is read as RAW image data via
//  `data of artwork 1 of current track` (local bytes, fine). Nothing is fetched over HTTP.
//

import AppKit
import Foundation

/// Runs AppleScript against Music.app to read the current track and drive transport.
///
/// This type is a pure helper with no published state; it is safe to call from a background
/// queue. It owns no mutable shared state, so it is `Sendable`.
struct AppleScriptNowPlaying: Sendable {

    /// AppleScript OSA error code returned when the user has not authorized Automation for
    /// the target app ("Not authorized to send Apple events to Music").
    private static let notAuthorizedErrorCode = -1743

    /// A field separator unlikely to appear in track metadata, used to join the text fields
    /// returned by the status script so we can split them back apart in Swift.
    private static let fieldSeparator = "\u{1F}" // ASCII Unit Separator

    // MARK: - Public API

    /// Read the current Apple Music snapshot. Runs AppleScript synchronously — call OFF the
    /// main thread. Returns `.empty` when Music is not running, nothing is playing, or the
    /// script is not authorized / errors out.
    func fetchSnapshot() -> NowPlayingInfo {
        // 1) Text fields (title / artist / album / state) in one round-trip. Guarded so we
        //    never launch Music just by asking.
        guard let fields = runStatusScript() else { return .empty }
        guard fields.state == "playing" || fields.state == "paused" else {
            // Stopped, or no current track.
            return .empty
        }

        // 2) Artwork as raw bytes in a second round-trip (may be absent → nil).
        let artwork = runArtworkScript()

        return NowPlayingInfo(
            title: fields.title.isEmpty ? nil : fields.title,
            artist: fields.artist.isEmpty ? nil : fields.artist,
            album: fields.album.isEmpty ? nil : fields.album,
            artwork: artwork?.image,
            isPlaying: fields.state == "playing",
            source: .appleMusicScript,
            sourceBundleID: "com.apple.Music",
            artworkKey: artwork?.key
        )
    }

    /// Toggle play/pause of Apple Music.
    func togglePlayPause() {
        runCommand("playpause")
    }

    /// Skip to the next track in Apple Music.
    func next() {
        runCommand("next track")
    }

    /// Skip to the previous track in Apple Music.
    func previous() {
        runCommand("previous track")
    }

    // MARK: - Status script

    private struct TrackFields {
        var title: String
        var artist: String
        var album: String
        var state: String
    }

    /// Reads player state + current track text in a single script. Returns `nil` when Music
    /// is not running or the script errors / is unauthorized.
    private func runStatusScript() -> TrackFields? {
        // `if application "Music" is running` avoids launching Music just to query it. When
        // not running we return the sentinel "not-running" so Swift maps it to `.empty`.
        // Fields are joined with the Unit Separator so we can split them unambiguously.
        let sep = Self.fieldSeparator
        let source = """
        if application "Music" is running then
            tell application "Music"
                set playerState to (player state as text)
                if playerState is "playing" or playerState is "paused" then
                    try
                        set trackName to (name of current track as text)
                    on error
                        set trackName to ""
                    end try
                    try
                        set trackArtist to (artist of current track as text)
                    on error
                        set trackArtist to ""
                    end try
                    try
                        set trackAlbum to (album of current track as text)
                    on error
                        set trackAlbum to ""
                    end try
                    return trackName & "\(sep)" & trackArtist & "\(sep)" & trackAlbum & "\(sep)" & playerState
                else
                    return "\(sep)\(sep)\(sep)" & playerState
                end if
            end tell
        else
            return "not-running"
        end if
        """

        guard let output = runAppleScriptString(source, context: "status") else { return nil }
        if output == "not-running" { return nil }

        let parts = output.components(separatedBy: sep)
        guard parts.count == 4 else { return nil }
        return TrackFields(title: parts[0], artist: parts[1], album: parts[2], state: parts[3])
    }

    // MARK: - Artwork script

    /// Reads the current track's artwork as raw image bytes, decoding to an `NSImage` on the
    /// calling (background) thread, keyed by `ArtworkKey.of` over all bytes (not
    /// `Data.hashValue`, which only covers the first 80). `nil` when absent or on any error.
    private func runArtworkScript() -> (image: NSImage, key: Int)? {
        let source = """
        if application "Music" is running then
            tell application "Music"
                try
                    return data of artwork 1 of current track
                on error
                    return missing value
                end try
            end tell
        else
            return missing value
        end if
        """

        guard let descriptor = runAppleScriptDescriptor(source, context: "artwork") else {
            return nil
        }
        // `missing value` comes back as a null/!data descriptor; its data will be empty.
        let data = descriptor.data
        guard !data.isEmpty, let image = NSImage(data: data) else { return nil }
        return (image: image, key: ArtworkKey.of(data))
    }

    // MARK: - Transport

    private func runCommand(_ command: String) {
        let source = """
        if application "Music" is running then
            tell application "Music" to \(command)
        end if
        """
        _ = runAppleScriptDescriptor(source, context: "command:\(command)")
    }

    // MARK: - AppleScript execution

    /// Compile + run an AppleScript source, returning the result descriptor. Centralizes
    /// error handling: logs and returns `nil` on compile/run failure, specifically calling
    /// out the Automation authorization error (-1743).
    private func runAppleScriptDescriptor(_ source: String, context: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            NSLog("[AgoyNotch] AppleScript compile failed (\(context)).")
            return nil
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            if code == Self.notAuthorizedErrorCode {
                NSLog("[AgoyNotch] Not authorized to control Music (code \(code)). "
                    + "Grant Automation permission in System Settings → Privacy & Security → Automation.")
            } else {
                let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "unknown error"
                NSLog("[AgoyNotch] AppleScript error (\(context)) code \(code): \(message)")
            }
            return nil
        }
        return result
    }

    /// Convenience over `runAppleScriptDescriptor` for scripts that return a text string.
    private func runAppleScriptString(_ source: String, context: String) -> String? {
        runAppleScriptDescriptor(source, context: context)?.stringValue
    }
}
