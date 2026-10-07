//
//  NotchWindowController.swift
//  AgoyNotch
//
//  Measures the hardware notch and places the fixed-size overlay window so its TOP edge is
//  the physical top of the screen (`screen.frame.maxY`), centered on the notch. Repositions
//  live when a geometry setting changes or the display configuration changes. The window
//  never resizes on expand/collapse — the grow-out-of-the-notch morph is pure SwiftUI
//  inside the window (see NotchView).
//
//  Note on coordinates: AppKit's screen origin is bottom-left, so the TOP edge of a screen
//  is `frame.maxY` and a top-anchored window's origin.y is `frame.maxY - windowHeight`.
//

import AppKit
import Combine
import SwiftUI

final class NotchWindowController: NSWindowController {

    private let viewModel: NotchViewModel
    private let settings: AppSettings
    private let hostingView: NotchHostingView

    /// Combine subscriptions (expand/collapse → tracking; geometry settings → reposition).
    private var cancellables = Set<AnyCancellable>()

    /// Notch size used on Macs without a hardware notch.
    private static let fallbackNotchSize = CGSize(width: 200, height: 32)

    /// Observer token. `nonisolated(unsafe)` because the nonisolated `deinit` reads it; it is
    /// written once in `init` and only read again in `deinit`, so there is no race.
    nonisolated(unsafe) private var screenParamsObserver: NSObjectProtocol?

    init(viewModel: NotchViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings

        let hosting = NotchHostingView(rootView: NotchView(viewModel: viewModel))
        // The SwiftUI content must never drive the window size: the window is resized only
        // by `positionWindow()` when a geometry setting changes.
        hosting.sizingOptions = []
        self.hostingView = hosting

        let panel = NotchWindow(
            contentRect: NSRect(origin: .zero, size: viewModel.windowSize),
            hostingView: hosting
        )

        super.init(window: panel)

        // Forward hover events from the hosting view's tracking area to the view model.
        hosting.onHoverChange = { [weak viewModel] isInside in
            viewModel?.hoverChanged(isInside)
        }

        // HOVER rect (see NotchHostingView.trackingRectProvider):
        //  • COLLAPSED → only the hover zone over the notch (Settings → Hover area).
        //  • EXPANDED  → the whole panel (plus the hover zone, in case it is offset below
        //    the panel), so the cursor can reach the transport buttons.
        hosting.trackingRectProvider = { [weak viewModel, weak hosting] in
            guard let viewModel, let hosting else { return nil }
            let hoverRect = Self.topCenteredRect(
                viewModel.hoverSize,
                topInset: CGFloat(viewModel.settings.hoverVerticalOffset),
                in: hosting
            )
            guard viewModel.isExpanded else { return hoverRect }
            return Self.topCenteredRect(viewModel.panelSize, in: hosting).union(hoverRect)
        }

        // CLICK rect: nothing while collapsed (clicks pass through), the panel while expanded.
        hosting.interactiveRectProvider = { [weak viewModel, weak hosting] in
            guard let viewModel, let hosting else { return nil }
            guard viewModel.isExpanded else { return .zero }
            return Self.topCenteredRect(viewModel.panelSize, in: hosting)
        }

        // Swap the tracked rect between hover zone and panel on every expand/collapse.
        viewModel.$isExpanded
            .receive(on: RunLoop.main)
            .sink { [weak hosting] _ in
                hosting?.refreshTracking()
            }
            .store(in: &cancellables)

        // Re-apply geometry LIVE when any geometry setting changes. `@Published` emits on
        // willSet (before the new value is stored); `receive(on:)` defers the sink to the
        // next run-loop pass, so `positionWindow()` reads the NEW values.
        let geometryChanges: [AnyPublisher<Void, Never>] = [
            settings.$hoverWidth.map { _ in () }.eraseToAnyPublisher(),
            settings.$hoverHeight.map { _ in () }.eraseToAnyPublisher(),
            settings.$hoverVerticalOffset.map { _ in () }.eraseToAnyPublisher(),
            settings.$horizontalOffset.map { _ in () }.eraseToAnyPublisher(),
            settings.$panelWidth.map { _ in () }.eraseToAnyPublisher(),
            settings.$panelHeight.map { _ in () }.eraseToAnyPublisher(),
        ]
        // (Each @Published also replays its current value on subscribe; that just triggers
        // one harmless extra positionWindow() right after launch.)
        Publishers.MergeMany(geometryChanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.positionWindow()
            }
            .store(in: &cancellables)

        // Reposition when the display configuration changes. The observer block is
        // @Sendable, so hop to the main actor instead of calling positionWindow() directly.
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.positionWindow()
            }
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

    /// A `size` rect, horizontally centered and hugging the TOP edge of the hosting view
    /// (optionally `topInset` points below it), in the hosting view's coordinates. Handles
    /// both flipped and non-flipped hosting views.
    private static func topCenteredRect(_ size: CGSize,
                                        topInset: CGFloat = 0,
                                        in hosting: NotchHostingView) -> CGRect {
        let full = hosting.bounds
        let w = min(size.width, full.width)
        let h = min(size.height, full.height)
        let x = full.midX - w / 2
        let y = hosting.isFlipped ? full.minY + topInset : full.maxY - topInset - h
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Finds the screen with a hardware notch, or falls back to the main screen.
    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// The bare hardware notch size: width = screen width minus the usable menu-bar areas
    /// either side of the notch; height = the top safe-area inset. No slack, no adjustments.
    private func measuredNotchSize(for screen: NSScreen?) -> CGSize {
        guard let screen, screen.safeAreaInsets.top > 0 else { return Self.fallbackNotchSize }
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0
        let width = screen.frame.width - left - right
        let height = screen.safeAreaInsets.top
        guard width > 0, height > 0 else { return Self.fallbackNotchSize }
        return CGSize(width: width, height: height)
    }

    // MARK: - Placement

    /// Sizes and places the window: top edge at `screen.frame.maxY` (the physical top of
    /// the display — `frame`, never `visibleFrame`, which stops below the menu bar),
    /// centered on the notch plus the horizontal offset. There is deliberately no vertical
    /// offset for the window: moving it down would re-create the gap under the notch.
    func positionWindow() {
        guard let window else { return }
        let screen = notchScreen()

        // 1. Measure. Assign only on change: the assignment fires objectWillChange and we do
        //    not want redundant redraws (measuredNotchSize is not a geometry trigger, so
        //    there is no feedback loop either way).
        let notch = measuredNotchSize(for: screen)
        if settings.measuredNotchSize != notch {
            settings.measuredNotchSize = notch
        }

        // 2. Size (depends on the measured notch through the hover size).
        let size = viewModel.windowSize
        guard let screenFrame = screen?.frame else {
            window.setContentSize(size)
            hostingView.refreshTracking()
            return
        }

        // 3. Place: top edge = screen top. NotchWindow.constrainFrameRect keeps AppKit from
        //    pushing it below the menu bar.
        let originX = screenFrame.midX - size.width / 2 + CGFloat(settings.horizontalOffset)
        let originY = screenFrame.maxY - size.height
        window.setFrame(NSRect(x: originX, y: originY, width: size.width, height: size.height),
                        display: true)

        // 4. The hover zone / panel rects may have changed.
        hostingView.refreshTracking()

        #if DEBUG
        print("[AgoyNotch] screen.maxY=\(screenFrame.maxY) window.maxY=\(window.frame.maxY) "
              + "notch=\(notch) safeArea.top=\(screen?.safeAreaInsets.top ?? 0) "
              + "hosting.safeAreaInsets.top=\(hostingView.safeAreaInsets.top)")
        #endif
    }

    /// Shows the panel and performs the initial placement.
    func show() {
        positionWindow()
        window?.orderFrontRegardless()
    }
}
