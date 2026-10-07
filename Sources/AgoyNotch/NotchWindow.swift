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
            self.trackingArea = nil
        }
        // Phantom-expand bug fix: the window is a FIXED expanded size (big enough to hold
        // the dropped panel) and anchored at the top of the screen. A tracking area covering
        // the whole `bounds` (previously via `.inVisibleRect`) therefore spanned the entire
        // large region BELOW the notch too, so any cursor crossing that transparent area
        // expanded the panel even when it was nowhere near the real notch.
        //
        // Instead, track ONLY the currently-interactive painted region (the same rect
        // `interactiveRectProvider` returns for the current state):
        //   • COLLAPSED → just the small pill over the physical notch, so moving the cursor
        //     elsewhere over the transparent window does NOT expand.
        //   • EXPANDED  → the full dropped panel (notchInset + expandedSize.height), so the
        //     cursor can travel from the notch down onto the transport buttons without
        //     leaving the tracked region (preserves the hover-collapse fix).
        //
        // `.inVisibleRect` is intentionally dropped so the explicit `rect:` is honoured.
        // `refreshTracking()` re-runs this whenever the state (collapsed↔expanded) or the
        // collapsed size changes, swapping the tracked rect between the two sizes.
        let trackedRect = interactiveRectProvider?() ?? bounds
        let area = NSTrackingArea(
            rect: trackedRect,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// Rebuilds the tracking area against the CURRENT interactive rect. The controller calls
    /// this whenever `viewModel.isExpanded` toggles or the collapsed size changes, so the
    /// tracked region switches between the small collapsed pill and the large expanded panel.
    func refreshTracking() {
        updateTrackingAreas()
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
        // Click pass-through: the window is a FIXED expanded size. Clicks are restricted to
        // the currently-painted region by the hosting view's `hitTest` (which returns `nil`
        // everywhere except the small collapsed pill or the full expanded panel), so clicks
        // over the surrounding transparent area pass through to the desktop/other apps.
        // Hover, by contrast, is now scoped by the NSTrackingArea itself (see
        // `NotchHostingView.updateTrackingAreas`) to that same interactive region, so the
        // cursor only expands the panel when it is actually over the notch pill — not merely
        // somewhere over the big transparent window.
        ignoresMouseEvents = false
        // Visible on every Space and over full-screen apps; does not move itself.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView = hostingView
    }

    // Never steal focus from the user's active app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
