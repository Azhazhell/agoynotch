//
//  MessageBadge.swift
//  AgoyNotch
//
//  Pure model for the Messages / WhatsApp unread badges shown in the open panel. Foundation
//  only (no AppKit, no app types), so the Linux self-test harness can compile it alone. The
//  badge text comes from the app's Dock badge; message content is never read.
//

import Foundation

/// The chat apps whose Dock badge AgoyNotch can show.
enum MessageApp: String, CaseIterable, Sendable {
    case messages
    case whatsapp

    /// Bundle IDs to look for, in preference order. WhatsApp: the native app, then the old
    /// Electron app.
    var bundleIDs: [String] {
        switch self {
        case .messages: return ["com.apple.MobileSMS"]
        case .whatsapp: return ["net.whatsapp.WhatsApp", "desktop.WhatsApp"]
        }
    }

    /// Label of the per-app toggle in Settings.
    var settingsTitle: String {
        switch self {
        case .messages: return "Messages (iMessage)"
        case .whatsapp: return "WhatsApp"
        }
    }

    /// SF Symbol used when the app's icon cannot be looked up.
    var fallbackSymbol: String {
        switch self {
        case .messages: return "message.fill"
        case .whatsapp: return "bubble.left.and.bubble.right.fill"
        }
    }
}

/// One app's badge as shown in the panel: the logo plus the (normalized) count.
struct MessageBadge: Equatable, Identifiable, Sendable {
    let app: MessageApp
    /// The running app that matched (used for its icon).
    let bundleID: String
    /// Normalized badge text, e.g. "3", "99+", "•".
    let label: String

    var id: MessageApp { app }
}

/// A running chat app the Dock reader should look for.
struct DockBadgeTarget: Sendable {
    let app: MessageApp
    let bundleID: String
    let localizedName: String?
}

enum BadgeLabel {
    /// Dock badge text → what the panel shows, or nil for "no badge".
    /// Numbers: ≤ 0 → nil, > 99 → "99+". Anything else: its first 3 characters.
    static func normalize(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if let n = Int(text) {
            if n <= 0 { return nil }
            if n > 99 { return "99+" }
            return String(n)
        }
        return String(text.prefix(3))
    }
}
