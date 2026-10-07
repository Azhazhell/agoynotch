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

    /// Supplies the current HIT-TEST region for click pass-through, in this view's
    /// coordinate space. This is DECOUPLED from the hover-tracking region (see
    /// `trackingRectProvider`): NSTrackingArea and hitTest are independent — hover can fire
    /// at points where hitTest returns `nil`.
    ///   • COLLAPSED → an EMPTY rect, because the collapsed state paints nothing, so clicks
    ///     over the (invisible) notch region must pass straight through to the menu bar /
    ///     desktop behind it.
    ///   • EXPANDED  → the full painted panel, so clicks land on the transport buttons.
    /// `nil` means "accept clicks everywhere" (defensive fallback). Set by the controller.
    var interactiveRectProvider: (() -> CGRect?)?

    /// Supplies the current HOVER-TRACKING region, in this view's coordinate space. This is
    /// INDEPENDENT of `interactiveRectProvider` (the hit-test region): drawing and clicks
    /// are decoupled from hover.
    ///   • COLLAPSED → the small notch-sized rect at the TOP CENTER (over the physical
    ///     notch), EVEN THOUGH nothing is drawn there — so moving the cursor onto the real
    ///     notch still fires `mouseEntered` and expands the panel.
    ///   • EXPANDED  → the full dropped panel (notchInset + expandedSize.height), so the
    ///     cursor can travel from the notch down onto the transport buttons without leaving
    ///     the tracked region.
    /// `nil` falls back to the whole `bounds`. Set by the controller.
    var trackingRectProvider: (() -> CGRect?)?

    private var trackingArea: NSTrackingArea?

    // "Hangs below the notch" fix (PRIME ROOT CAUSE): on a notched Mac the window's top
    // edge sits at the physical top of the display, so this hosting view's safe area
    // includes the hardware notch at the top. By default NSHostingView insets its SwiftUI
    // content by that safe area, pushing the top-anchored collapsed pill DOWN by exactly
    // the notch height — which is why the black overlay appeared *below* the real notch in
    // the menu-bar strip instead of fused with it. Returning zero insets here stops AppKit
    // from reserving the notch region, so the SwiftUI content's top edge == this view's top
    // edge == the window top == the physical screen top. (`NotchView` also applies
    // `.ignoresSafeArea()` as a belt-and-suspenders on the SwiftUI side.)
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }

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
        //
        // DECOUPLED FROM DRAWING / CLICKS: this uses `trackingRectProvider`, NOT
        // `interactiveRectProvider`. While collapsed the view paints nothing and the
        // hit-test rect is empty (clicks pass through), yet the tracked rect here is still
        // the small notch-sized rect at the top center — so hovering the real hardware
        // notch still fires `mouseEntered` and expands the panel.
        let trackedRect = trackingRectProvider?() ?? bounds
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

    /// Only the currently-painted region should swallow clicks; everything else must pass
    /// clicks through to whatever is behind the overlay (desktop, other apps, the menu bar).
    ///   • COLLAPSED → the view paints nothing, so `interactiveRectProvider` returns an
    ///     EMPTY rect and EVERY click over the (invisible) notch region passes through.
    ///   • EXPANDED  → the hit region is the full dropped panel, so clicks hit the
    ///     transport buttons.
    /// Returning `nil` from `hitTest` makes a point transparent to clicks WITHOUT affecting
    /// the NSTrackingArea (which uses `trackingRectProvider`), so hover-to-expand still
    /// fires over the physical notch even while collapsed clicks pass straight through. This
    /// is the drawing/clicks ↔ hover decoupling in action.
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
