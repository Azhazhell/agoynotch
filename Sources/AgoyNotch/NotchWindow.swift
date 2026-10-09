//
//  NotchWindow.swift
//  AgoyNotch
//
//  A borderless, transparent, non-activating NSPanel whose top edge sits at the physical
//  top of the screen, over the hardware notch and the menu bar. It never becomes key/main,
//  so hovering or clicking it never steals focus from the user's current app. Hover is
//  decided by NotchWindowController from the cursor position in SCREEN coordinates; the
//  NSTrackingArea on the hosting view is only a fast path that pings the controller on
//  enter/exit (it fires only while the window accepts mouse events, i.e. when expanded).
//  While collapsed the window ignores mouse events entirely (click-through).
//

import AppKit
import SwiftUI

/// Hosting view subclass that owns the tracking area and forwards enter/exit events.
/// Uses NSHostingView's inherited initializers.
final class NotchHostingView: NSHostingView<NotchView> {

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

    /// Rebuilds the tracking area against the CURRENT tracking rect, then asks the controller
    /// to re-evaluate hover from the real cursor position. The controller calls this when
    /// `isExpanded` toggles and whenever a geometry setting changes.
    func refreshTracking() {
        updateTrackingAreas()
        onPointerEvent?()
    }

    // MARK: - Pointer events (fast path only)

    /// Called on every tracking-area enter/exit. It carries NO inside/outside value: the
    /// controller evaluates hover from `NSEvent.mouseLocation` in screen coordinates, so a
    /// stale, spurious or boundary event location can never flip the hover state.
    var onPointerEvent: (() -> Void)?

    override func mouseEntered(with event: NSEvent) {
        #if DEBUG
        print("[AgoyNotch] mouseEntered")
        #endif
        onPointerEvent?()
    }

    override func mouseExited(with event: NSEvent) {
        #if DEBUG
        print("[AgoyNotch] mouseExited")
        #endif
        onPointerEvent?()
    }

    // MARK: - Click pass-through

    /// The app is never active, so the first click must act (badges, Now Playing, buttons).
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// While expanded (the only time the window accepts mouse events), only the painted
    /// panel swallows clicks; everywhere else returns `nil` so clicks pass through.
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
        // fuses with the hardware notch into one shape. `.nonactivatingPanel`, so even when the
        // expanded panel becomes key the raised level never activates the app or steals focus.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        isFloatingPanel = true
        isMovableByWindowBackground = false
        // The panel starts COLLAPSED, so it starts click-through: clicks go straight to the
        // menu-bar items beside the notch. Hover is detected from the cursor position (not
        // from events reaching this window), and NotchWindowController turns mouse events
        // back on just before the panel expands (so the buttons work) and off on collapse.
        // Inside the expanded window, NotchHostingView.hitTest still passes through clicks
        // outside the painted panel.
        ignoresMouseEvents = true
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

    // A `.nonactivatingPanel` becoming key does NOT activate the app or pull focus from the
    // user's foreground app — that is the point of a nonactivating panel. We DO need to be
    // key while expanded, though: a borderless, never-key panel at this very high level does
    // not reliably receive the first mouse-DOWN, so SwiftUI Buttons / tap gestures inside the
    // hosting view never fire (hitTest finds the view but the click is dropped). Allowing key
    // lets the expanded panel receive clicks. While collapsed the window ignores mouse events
    // (click-through) and is never made key, so this never shows focus or grabs clicks there.
    override var canBecomeKey: Bool { true }
    // Never become MAIN — that would make us the app's primary window and could steal focus.
    override var canBecomeMain: Bool { false }
}
