//
//  NotchWindow.swift
//  MacNotch
//
//  A borderless, transparent, non-activating NSPanel that floats over the hardware notch.
//  It never becomes key/main so hovering or clicking it never steals focus from the user's
//  current app. Hover is driven by an AppKit NSTrackingArea (SwiftUI `.onHover` over a
//  transparent non-activating panel is unreliable), installed on the hosting view and
//  forwarded to the view model.
//

import AppKit
import SwiftUI

/// Hosting view subclass that owns the tracking area and forwards enter/exit events.
final class NotchHostingView: NSHostingView<NotchView> {

    /// Called with `true` on mouse-enter and `false` on mouse-exit.
    var onHoverChange: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}

/// The floating notch panel.
final class NotchWindow: NSPanel {

    init(contentRect: NSRect, hostingView: NSView) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        isFloatingPanel = true
        isMovableByWindowBackground = false
        // Needed so the hover tracking area receives events. The transparent region
        // outside the pill is handled by the view's own hit-testing.
        ignoresMouseEvents = false
        // Visible on every Space and over full-screen apps; does not move itself.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView = hostingView
    }

    // Never steal focus from the user's active app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
