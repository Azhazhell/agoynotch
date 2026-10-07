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

    /// Supplies the current hit-test region for click pass-through. In screen-free view
    /// coordinates (origin top-left of this view). When collapsed, this is just the small
    /// pill at the top; when expanded it is the whole panel. `nil` means "accept clicks
    /// everywhere" (defensive fallback). Set by the controller.
    var interactiveRectProvider: (() -> CGRect?)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        // Hover stability (THE bug fix): the window is now a FIXED expanded size and never
        // resizes on hover, so this tracking area permanently covers the entire interactive
        // panel. `.inVisibleRect` keeps it matched to the view's full bounds. Because the
        // tracked region already spans from the notch down to the transport buttons, moving
        // the cursor from the notch onto the buttons never crosses the region's edge — so no
        // spurious `mouseExited` fires and the panel does not collapse out from under the
        // pointer. The 0.35s collapse debounce in NotchViewModel is a secondary safeguard
        // for brief slips near the true outer edge.
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

    // MARK: - Click pass-through

    /// Only the currently-painted region (collapsed pill or expanded panel) should swallow
    /// clicks; the surrounding transparent area must pass clicks through to whatever is
    /// behind the overlay (desktop, other apps). Returning `nil` from `hitTest` makes a
    /// point transparent to clicks WITHOUT affecting the NSTrackingArea, so hover-to-expand
    /// still fires everywhere over the window. This is how we keep hover working while not
    /// permanently blocking the large transparent expanded-sized frame when collapsed.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let provider = interactiveRectProvider, let interactive = provider() else {
            // No provider configured → behave normally (accept clicks).
            return super.hitTest(point)
        }
        // `point` is in the superview's coordinate space; convert to this view's space.
        let local = convert(point, from: superview)
        guard interactive.contains(local) else {
            return nil // transparent to clicks here
        }
        return super.hitTest(point)
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
        // Click pass-through (review finding #1): the window is now a FIXED expanded size
        // (so the tracking area always covers the whole panel — the hover-collapse bug fix).
        // A large interactive window would otherwise swallow clicks over the big transparent
        // area while collapsed. We avoid that WITHOUT turning off mouse events — instead the
        // hosting view's `hitTest` returns `nil` everywhere except the currently-painted
        // region (the small pill when collapsed, the full panel when expanded). `hitTest`
        // does not affect NSTrackingArea, so hover still fires across the whole window and
        // expands the panel, while clicks over the transparent area pass through to the
        // desktop/other apps. Over the physical notch itself there is no usable screen
        // anyway, so swallowing clicks on the collapsed pill costs the user nothing.
        ignoresMouseEvents = false
        // Visible on every Space and over full-screen apps; does not move itself.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView = hostingView
    }

    // Never steal focus from the user's active app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
