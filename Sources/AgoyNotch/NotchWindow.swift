//
//  NotchWindow.swift
//  AgoyNotch
//
//  A borderless, transparent, non-activating NSPanel whose top edge sits at the physical
//  top of the screen, over the hardware notch and the menu bar. It never becomes key/main,
//  so hovering or clicking it never steals focus from the user's current app. Hover is
//  driven by an AppKit NSTrackingArea (SwiftUI `.onHover` over a transparent
//  non-activating panel is unreliable), installed on the hosting view and forwarded to the
//  view model.
//

import AppKit
import SwiftUI

/// Hosting view subclass that owns the tracking area and forwards enter/exit events.
/// Uses NSHostingView's inherited initializers.
final class NotchHostingView: NSHostingView<NotchView> {

    /// Called with `true` when the cursor enters the tracked rect and `false` when it leaves
    /// (reconciled against the real cursor position, see `reconcileHover`).
    var onHoverChange: ((Bool) -> Void)?

    /// Supplies the current CLICK region, in this view's coordinate space. Independent of
    /// the hover region (`trackingRectProvider`): NSTrackingArea and hitTest are separate in
    /// AppKit, so hover can fire where hitTest returns `nil`.
    ///   • COLLAPSED → empty: nothing is drawn, so clicks pass through to the menu bar.
    ///   • EXPANDED  → the panel, so clicks reach the transport buttons.
    /// `nil` means "accept clicks everywhere" (defensive fallback). Set by the controller.
    var interactiveRectProvider: (() -> CGRect?)?

    /// Supplies the current HOVER region, in this view's coordinate space.
    ///   • COLLAPSED → ONLY the hover zone over the notch (size/offset from Settings), never
    ///     the whole window — so the cursor elsewhere over the transparent window does not
    ///     open the panel.
    ///   • EXPANDED  → the whole panel, so the cursor can travel down onto the buttons
    ///     without leaving the tracked region.
    /// `nil` falls back to the whole `bounds`. Set by the controller.
    var trackingRectProvider: (() -> CGRect?)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        // An explicit rect (no `.inVisibleRect`) so only the provider's region is tracked.
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
    /// this when `isExpanded` toggles and whenever a geometry setting changes. Rebuilding
    /// while the cursor is inside can deliver a spurious exit, so the real cursor position
    /// is reconciled right after.
    func refreshTracking() {
        updateTrackingAreas()
        reconcileHover()
    }

    // MARK: - Position-based hover

    /// The last hover state reported through `onHoverChange`.
    private(set) var isPointerInside = false

    /// Whether the cursor is currently inside the tracked rect, from the REAL cursor
    /// position (not from enter/exit events, which can be lost or spurious).
    func pointerIsInTrackedRect(windowPoint: NSPoint? = nil) -> Bool {
        guard let window, window.isVisible else { return false }
        let p = windowPoint ?? window.convertPoint(fromScreen: NSEvent.mouseLocation)
        // 1 pt slop: CGRect.contains excludes maxY, which is the screen-top edge here.
        return (trackingRectProvider?() ?? bounds)
            .insetBy(dx: -1, dy: -1)
            .contains(convert(p, from: nil))
    }

    /// Reports a hover change only when the real inside/outside state differs from the last
    /// reported one, so spurious or duplicate events cannot wedge the open/close logic.
    func reconcileHover(windowPoint: NSPoint? = nil) {
        let inside = pointerIsInTrackedRect(windowPoint: windowPoint)
        guard inside != isPointerInside else { return }
        isPointerInside = inside
        #if DEBUG
        let rect = trackingRectProvider?() ?? bounds
        print("[AgoyNotch] hover inside=\(inside) rect=\(rect) mouse=\(NSEvent.mouseLocation)")
        #endif
        onHoverChange?(inside)
    }

    override func mouseEntered(with event: NSEvent) {
        #if DEBUG
        print("[AgoyNotch] mouseEntered")
        #endif
        reconcileHover(windowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        #if DEBUG
        print("[AgoyNotch] mouseExited")
        #endif
        reconcileHover(windowPoint: event.locationInWindow)
    }

    // MARK: - Click pass-through

    /// Only the painted panel swallows clicks; everywhere else returns `nil` so clicks pass
    /// through. Returning `nil` here does not affect the NSTrackingArea, so hover still
    /// fires over the notch while collapsed.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let provider = interactiveRectProvider, let interactive = provider() else {
            return super.hitTest(point)
        }
        // `point` is in the superview's coordinate space; convert to this view's space.
        let local = convert(point, from: superview)
        guard interactive.contains(local) else {
            return nil
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
        // Above the menu bar (mainMenu + 3, the level notch utilities use) so the panel's
        // black top band is drawn OVER the menu-bar strip on both sides of the notch and
        // fuses with the hardware notch into one shape. Never key/main + `.nonactivatingPanel`,
        // so the raised level never steals focus.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        isFloatingPanel = true
        isMovableByWindowBackground = false
        // Must stay interactive so the hover tracking area keeps firing. Click pass-through
        // outside the panel is handled by NotchHostingView.hitTest.
        ignoresMouseEvents = false
        // NSPanel defaults this to true: AppKit would HIDE the notch panel whenever the app
        // deactivates (e.g. the user clicks another app after Settings activated us), and a
        // hidden window's tracking area never fires — hover would be dead.
        hidesOnDeactivate = false
        // Every Space, over full-screen apps, not moved by Exposé, skipped by ⌘`.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        contentView = hostingView
    }

    /// AppKit normally constrains windows so they do not overlap the menu bar, which would
    /// push this panel down by the menu-bar height and leave a gap under the notch. Return
    /// the requested frame unchanged so the window top stays at `screen.frame.maxY`.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    // Never steal focus from the user's active app.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
