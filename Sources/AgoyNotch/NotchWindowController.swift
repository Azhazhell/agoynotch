//
//  NotchWindowController.swift
//  AgoyNotch
//
//  Measures the hardware notch geometry and positions the floating panel flush under it.
//  Recomputes on display reconfiguration. The window is a FIXED expanded size and never
//  resizes on collapse/expand — the collapsed↔expanded morph is a SwiftUI spring drawn
//  inside the window (see NotchViewModel.windowSize / NotchView). This controller only ever
//  places the window under the notch and layers the user's manual adjustments on top.
//
//  Note on coordinates: AppKit's screen origin is bottom-left, so the TOP edge of a screen
//  is `frame.maxY` and a top-anchored window's origin.y is `frame.maxY - windowHeight`.
//

import AppKit
import SwiftUI

final class NotchWindowController: NSWindowController {

    private let viewModel: NotchViewModel
    private let hostingView: NotchHostingView

    /// User fine-tuning (horizontal/vertical offset + width adjustment) layered on top of
    /// the auto-detected notch geometry. Loaded from UserDefaults; updated live from the
    /// menu-bar "Adjust Notch" commands via `applySettings(_:)`.
    private var settings = NotchSettings()

    /// Fallback collapsed size for Macs without a hardware notch.
    private let fallbackCollapsedSize = CGSize(width: 220, height: 32)

    private var screenParamsObserver: NSObjectProtocol?

    init(viewModel: NotchViewModel) {
        self.viewModel = viewModel

        // Build the hosting view + panel.
        let rootView = NotchView(viewModel: viewModel)
        let hosting = NotchHostingView(rootView: rootView)
        self.hostingView = hosting

        // Create the window at its permanent (expanded) size. `positionWindow` will place
        // it under the notch; it never resizes the window afterwards.
        let panel = NotchWindow(
            contentRect: NSRect(origin: .zero, size: viewModel.windowSize),
            hostingView: hosting
        )

        super.init(window: panel)

        // Forward hover events from the hosting view's tracking area to the view model.
        hosting.onHoverChange = { [weak viewModel] isInside in
            viewModel?.hoverChanged(isInside)
        }

        // Supply the click pass-through region. The window is permanently the expanded size
        // but the painted content (collapsed pill or expanded panel) is top-centered inside
        // it. Only that painted region should swallow clicks; the surrounding transparent
        // area passes clicks through to the desktop/other apps. The hosting view is NOT
        // flipped (AppKit default origin bottom-left), while the SwiftUI content is drawn
        // top-anchored — so the interactive rect hugs the TOP edge (high y) of the view.
        hosting.interactiveRectProvider = { [weak viewModel, weak hosting] in
            guard let viewModel, let hosting else { return nil }
            let full = hosting.bounds
            let painted = viewModel.isExpanded ? viewModel.expandedSize : viewModel.collapsedSize
            let width = min(painted.width, full.width)
            let height = min(painted.height, full.height)
            let x = full.midX - width / 2
            // The content is drawn top-anchored. The on-screen TOP edge is `maxY` in a
            // non-flipped view and `minY` in a flipped one, so pick the right edge based on
            // `isFlipped` to stay correct regardless of NSHostingView's flip convention.
            let y = hosting.isFlipped ? full.minY : full.maxY - height
            return CGRect(x: x, y: y, width: width, height: height)
        }

        // Reposition whenever the display configuration changes (resolution, arrangement,
        // a display plugged/unplugged, etc.).
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.positionWindow(animated: false)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        if let screenParamsObserver {
            NotificationCenter.default.removeObserver(screenParamsObserver)
        }
    }

    // MARK: - Geometry

    /// Finds the screen with a hardware notch, or falls back to the main screen.
    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Measures the collapsed pill size from the notch geometry (or fallback), then applies
    /// the user's `widthAdjustment` on top. The width is clamped to a small positive minimum
    /// so an over-aggressive "Narrower" cannot collapse the pill to zero/negative width.
    private func measuredCollapsedSize(for screen: NSScreen?) -> CGSize {
        let base: CGSize
        if let screen, screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let notchWidth = screen.frame.width - left - right
            let notchHeight = screen.safeAreaInsets.top
            // Guard against degenerate measurements.
            base = (notchWidth > 0 && notchHeight > 0)
                ? CGSize(width: notchWidth, height: notchHeight)
                : fallbackCollapsedSize
        } else {
            base = fallbackCollapsedSize
        }

        let adjustedWidth = max(1, base.width + settings.widthAdjustment)
        return CGSize(width: adjustedWidth, height: base.height)
    }

    // MARK: - Placement

    /// Positions the FIXED-SIZE panel under the notch (or top-center on non-notch Macs).
    ///
    /// The window is always the expanded size (`viewModel.windowSize`) — it never resizes
    /// when the panel expands or collapses. That fixed, top-anchored frame is what keeps the
    /// hover tracking area covering the whole interactive area (see `NotchWindow` /
    /// `NotchHostingView` and `viewModel.windowSize` for the full rationale). This method is
    /// therefore only about PLACEMENT, not sizing-on-state-change.
    func positionWindow(animated: Bool) {
        guard let window else { return }
        let screen = notchScreen()

        // Update the view model's collapsed size from the real measurement so the SwiftUI
        // pill (drawn inside the fixed window) hugs the notch exactly. widthAdjustment is
        // baked in here and only affects the drawn pill, not the window frame.
        let collapsed = measuredCollapsedSize(for: screen)
        viewModel.updateCollapsedSize(collapsed)

        // The window is always the expanded size.
        let size = viewModel.windowSize
        guard let screenFrame = screen?.frame else {
            window.setContentSize(size)
            return
        }

        // Start from the auto-detected placement: horizontally centered on the notch and
        // pinned to the top edge (maxY in AppKit's bottom-left coordinate space). Because
        // the window is the expanded width, centering it on the notch also centers the
        // collapsed pill (which SwiftUI draws top-centered inside the window).
        var originX = screenFrame.midX - size.width / 2
        var originY = screenFrame.maxY - size.height

        // Layer the user's manual adjustments on top of the auto-detected placement.
        //  • horizontalOffset: positive moves the overlay right, so add directly to X.
        //  • verticalOffset: positive nudges the overlay DOWN. Because AppKit's origin is
        //    bottom-left, moving down means DECREASING originY, so we subtract it.
        // These shift the WHOLE fixed-size overlay so it lines up with the real notch;
        // widthAdjustment is handled separately (it only tunes the drawn collapsed pill).
        originX += settings.horizontalOffset
        originY -= settings.verticalOffset

        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        // Never animate the frame: the window size is constant, so there is nothing to
        // animate here. The collapsed↔expanded morph is a SwiftUI spring inside the window.
        window.setFrame(frame, display: true, animate: false)
    }

    /// Shows the panel and performs the initial placement.
    func show() {
        positionWindow(animated: false)
        window?.orderFrontRegardless()
    }

    // MARK: - Manual adjustment

    /// Replace the current adjustment settings and immediately reposition the window so the
    /// change is visible as the user taps a menu item. The caller (AppDelegate) owns the
    /// `NotchSettings` value, mutates it, persists it, and hands the new value here.
    func applySettings(_ newSettings: NotchSettings) {
        settings = newSettings
        positionWindow(animated: false)
    }
}
