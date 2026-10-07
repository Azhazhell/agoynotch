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
    ///   • EXPANDED  → the full grown panel (expandedSize, flush at the top), so the cursor
    ///     can travel from the notch down onto the transport buttons without leaving the
    ///     tracked region.
    /// `nil` falls back to the whole `bounds`. Set by the controller.
    var trackingRectProvider: (() -> CGRect?)?

    private var trackingArea: NSTrackingArea?

    // "Hangs below the notch" fix (PRIME ROOT CAUSE): on a notched Mac the window's top
    // edge sits at the physical top of the display, so this hosting view's safe area
    // includes the hardware notch at the top. By default NSHostingView insets its SwiftUI
    // content by that safe area, pushing the top-anchored collapsed pill / expanded panel
    // DOWN by exactly the notch height — which is why the black overlay appeared *below*
    // the real notch (a separate box with a gap at the top) instead of fused with it.
    //
    // There are TWO layers that must be defeated for the gap to close:
    //
    //  1. The AppKit NSView safe-area insets. Returning zero here stops AppKit from
    //     reporting the notch as a safe-area inset, so the SwiftUI content's top edge ==
    //     this view's top edge == the window top == the physical screen top.
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsetsZero }

    //  2. NSHostingView's OWN safe-area handling. On macOS 13.3+ the hosting view decides
    //     which safe-area regions to apply to its SwiftUI content via `safeAreaRegions`.
    //     Overriding the NSView `safeAreaInsets` above is NOT always enough — the prior
    //     attempt kept that override AND `.ignoresSafeArea()` on the root yet the gap
    //     persisted, because the hosting view was still reserving the container's safe-area
    //     region (the notch). Clearing `safeAreaRegions` to an empty set tells the hosting
    //     view to apply NO safe-area regions at all, so the SwiftUI content is laid out
    //     edge-to-edge from the physical top. `sizingOptions` is left at its default (we do
    //     NOT want the hosting view to resize the window — the window is a fixed expanded
    //     size by design).
    //
    // Both are set in `init` because they are stored configuration, not overrides. The
    // tracking-area / hitTest logic below is untouched.
    //
    // `NSHostingView.init(rootView:)` is a `required` designated initializer, so the
    // override is written with `required` (not `override`) per Swift's initializer rules.
    required init(rootView: NotchView) {
        super.init(rootView: rootView)
        // macOS 13.3+. The deployment target is macOS 15, so this is always available, but
        // guard anyway to stay robust if the target is ever lowered.
        if #available(macOS 13.3, *) {
            safeAreaRegions = []
        }
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        // Phantom-expand bug fix: the window is a FIXED expanded size (big enough to hold
        // the grown panel) and anchored at the top of the screen. A tracking area covering
        // the whole `bounds` (previously via `.inVisibleRect`) therefore spanned the entire
        // large region BELOW the notch too, so any cursor crossing that transparent area
        // expanded the panel even when it was nowhere near the real notch.
        //
        // Instead, track ONLY the notch-sized region for the current state (the rect
        // `trackingRectProvider` returns):
        //   • COLLAPSED → just the small rect over the physical notch, so moving the cursor
        //     elsewhere over the transparent window does NOT expand. (Nothing is PAINTED
        //     here while collapsed — tracking is decoupled from drawing.)
        //   • EXPANDED  → the full grown panel (expandedSize, flush at the top), so the
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

    /// Rebuilds the tracking area against the CURRENT tracking rect. The controller calls
    /// this whenever `viewModel.isExpanded` toggles or the collapsed size changes, so the
    /// tracked region switches between the small collapsed notch rect (invisible but still
    /// hover-sensitive) and the large expanded panel.
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
    ///   • EXPANDED  → the hit region is the full grown panel (flush at the top), so clicks
    ///     hit the transport buttons.
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
        // WINDOW LEVEL: `.statusBar` sits at the menu-bar layer, so the panel can draw OVER
        // the menu-bar strip and right up to the physical top of the display — essential now
        // that the panel's top band must fuse with the hardware notch with no gap. (A higher
        // level such as a shielding level is unnecessary and would also float over system
        // UI; `.statusBar` is enough to overlap the menu bar.) The panel never becomes
        // key/main (see `canBecomeKey`/`canBecomeMain` below) + `.nonactivatingPanel`, so it
        // never steals focus from the user's active app despite the raised level.
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
