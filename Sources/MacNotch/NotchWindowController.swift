//
//  NotchWindowController.swift
//  MacNotch
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

    /// Measures the collapsed pill size from the notch geometry (or fallback).
    private func measuredCollapsedSize(for screen: NSScreen?) -> CGSize {
        guard let screen, screen.safeAreaInsets.top > 0 else {
            return fallbackCollapsedSize
        }
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let notchWidth = screen.frame.width - left - right
        let notchHeight = screen.safeAreaInsets.top

        // Guard against degenerate measurements.
        guard notchWidth > 0, notchHeight > 0 else { return fallbackCollapsedSize }
        return CGSize(width: notchWidth, height: notchHeight)
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

        // Horizontally centered on the notch; pinned to the top edge (maxY).
        let originX = screenFrame.midX - size.width / 2
        let originY = screenFrame.maxY - size.height
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
}
