//
//  MessageBadgesView.swift
//  AgoyNotch
//
//  The Messages / WhatsApp badges in the open panel's top band, left of the camera: the
//  app's icon with its unread count, and nothing else. Apps with no badge are not shown.
//  Also the optional small red dot beside the notch while collapsed (off by default).
//

import SwiftUI

struct MessageBadgesRow: View {
    let badges: [MessageBadge]
    /// Called after a badge click opened its app (the panel then closes).
    var onOpen: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            ForEach(badges) { badge in
                Button {
                    AppLauncher.activate(bundleID: badge.bundleID)
                    onOpen()
                } label: {
                    BadgeIcon(badge: badge).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.2), value: badges)
    }
}

/// App icon + red count capsule in its top-right corner.
private struct BadgeIcon: View {
    let badge: MessageBadge

    var body: some View {
        AppIconImage(bundleID: badge.bundleID, size: 18, fallback: .symbol(badge.app.fallbackSymbol))
            .overlay(alignment: .topTrailing) {
                Text(badge.label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3.5)
                    .frame(minWidth: 13, minHeight: 13)
                    .background(Capsule().fill(MessageBadgeDot.red))
                    .fixedSize()
                    .offset(x: 6, y: -5)
            }
    }
}

extension View {
    /// Pointing-hand cursor while hovering a clickable element.
    func pointingHandCursor() -> some View {
        onHover { inside in
            // set() (not push/pop): the panel may collapse under the cursor without an exit.
            (inside ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }
}

/// The optional collapsed indicator: a small red dot just right of the hardware notch.
struct MessageBadgeDot: View {
    static let red = Color(red: 1, green: 0.23, blue: 0.19)
    static let size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(Self.red)
            .frame(width: Self.size, height: Self.size)
            .allowsHitTesting(false)
    }
}
