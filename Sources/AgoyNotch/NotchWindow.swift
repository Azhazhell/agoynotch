//
//  NotchWindow.swift
//  AgoyNotch
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
        // Hover stability across resize (review finding #2): the tracking area is created
        // with `.inVisibleRect`, so AppKit continuously keeps it matched to the view's
        // CURRENT visible bounds instead of the fixed `rect` passed at creation time (the
        // `rect` is therefore ignored). As the window grows from the small collapsed pill
        // to the full expanded panel, the tracked region grows with it, so the cursor stays
        // "inside" the tracking area and the panel does not immediately re-collapse out from
        // under the pointer. The 0.35s collapse debounce in NotchViewModel is the second
        // layer of defense, smoothing over the brief moment during the resize animation.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // The window resizes on expand/collapse; refresh the tracking area so `.inVisibleRect`
        // is re-evaluated against the new bounds right away rather than on the next natural
        // tracking-areas pass. Reinforces finding #2's fix.
        updateTrackingAreas()
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
        // The window must stay interactive (`ignoresMouseEvents = false`) so the hover
        // tracking area keeps firing — hover-to-expand is the user's priority and must
        // never break.
        //
        // Click pass-through tradeoff (review finding #1): because the window is
        // interactive, it does intercept clicks over its own frame even when the collapsed
        // pill is drawn nearly invisibly (opacity ~0.001) with nothing playing. We minimize
        // the harm by keeping the COLLAPSED window frame no larger than the physical notch
        // itself (see NotchWindowController.measuredCollapsedSize): the notch is dead,
        // non-interactive screen space anyway, so intercepting clicks there costs the user
        // nothing. The window only grows past the notch once expanded — i.e. only while the
        // user is actively hovering it — so no usable screen area is permanently blocked.
        ignoresMouseEvents = false
        // Visible on every Space and over full-screen apps; does not move itself.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView = hostingView
    }

    // Never steal focus from the user's active app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
