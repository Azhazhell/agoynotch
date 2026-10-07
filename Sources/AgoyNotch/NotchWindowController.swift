//
//  NotchWindowController.swift
//  AgoyNotch
//
//  Measures the hardware notch geometry and positions the floating panel flush under it.
//  Recomputes on display reconfiguration. Resizes/recenters the panel when the view model
//  toggles between collapsed and expanded.
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

        let panel = NotchWindow(
            contentRect: NSRect(origin: .zero, size: fallbackCollapsedSize),
            hostingView: hosting
        )

        super.init(window: panel)

        // Forward hover events from the hosting view's tracking area to the view model.
        hosting.onHoverChange = { [weak viewModel] isInside in
            viewModel?.hoverChanged(isInside)
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

    /// Positions and sizes the panel under the notch (or top-center on non-notch Macs).
    func positionWindow(animated: Bool) {
        guard let window else { return }
        let screen = notchScreen()

        // Update the view model's collapsed size from the real measurement so the SwiftUI
        // content hugs the notch exactly.
        let collapsed = measuredCollapsedSize(for: screen)
        viewModel.updateCollapsedSize(collapsed)

        let size = viewModel.currentSize
        guard let screenFrame = screen?.frame else {
            window.setContentSize(size)
            return
        }

        // Start from the auto-detected placement: horizontally centered on the notch and
        // pinned to the top edge (maxY in AppKit's bottom-left coordinate space).
        var originX = screenFrame.midX - size.width / 2
        var originY = screenFrame.maxY - size.height

        // Layer the user's manual adjustments on top of the auto-detected placement.
        //  • horizontalOffset: positive moves the overlay right, so add directly to X.
        //  • verticalOffset: positive nudges the overlay DOWN. Because AppKit's origin is
        //    bottom-left, moving down means DECREASING originY, so we subtract it.
        // widthAdjustment is already baked into `size` via measuredCollapsedSize(), so the
        // pill still stays centered on the (offset-adjusted) center as it grows/shrinks.
        originX += settings.horizontalOffset
        originY -= settings.verticalOffset

        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        window.setFrame(frame, display: true, animate: animated)
    }

    /// Shows the panel and performs the initial placement.
    func show() {
        positionWindow(animated: false)
        window?.orderFrontRegardless()
    }

    /// Called when `isExpanded` changes so the panel grows/shrinks and recenters smoothly.
    func layoutForStateChange() {
        positionWindow(animated: true)
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
