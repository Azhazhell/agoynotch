//
//  AppIconViews.swift
//  AgoyNotch
//
//  The source app's real icon (e.g. Chrome, Spotify, TV) for the Now Playing panel and the
//  collapsed pill. These are the user's installed app icons rendered locally via
//  NSWorkspace; no trademark assets ship with AgoyNotch.
//

import AppKit
import SwiftUI

/// Bundle ID → icon, looked up once per launch (misses are remembered too).
@MainActor
enum AppIconCache {
    static var icons: [String: NSImage] = [:]
    static var missing: Set<String> = []

    static func icon(forBundleID bundleID: String) -> NSImage? {
        if let icon = icons[bundleID] { return icon }
        if missing.contains(bundleID) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }
}

/// The app icon for `bundleID`, or a fallback when unknown / not installed.
struct AppIconImage: View {
    enum Fallback {
        case musicGlyph
        case symbol(String)
    }

    let bundleID: String?
    let size: CGFloat
    let fallback: Fallback

    var body: some View {
        if let bundleID, let icon = AppIconCache.icon(forBundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            switch fallback {
            case .musicGlyph:
                AppleMusicGlyph(size: size)
            case .symbol(let name):
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay(
                        Image(systemName: name)
                            .font(.system(size: size * 0.55, weight: .semibold))
                            .foregroundStyle(.white)
                    )
            }
        }
    }
}
