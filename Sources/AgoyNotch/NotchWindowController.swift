//
//  NotchWindowController.swift
//  AgoyNotch
//
//  Measures the hardware notch and places the overlay window so its TOP edge is the
//  physical top of the screen (`screen.frame.maxY`), centered on the notch. Repositions
//  live when a geometry setting changes or the display configuration changes.
//
//  Window size: while COLLAPSED the window is exactly the hover zone (it covers only the
//  hardware notch, so it can never swallow clicks meant for other windows). Just before the
//  panel opens it grows to the expanded size; after the close animation it shrinks back.
//  The grow-out-of-the-notch morph itself is pure SwiftUI inside the window (see NotchView).
//
//  Visibility: the panel is re-ordered front whenever the app's activation state, the
//  Space or the screen configuration changes, so it can never be left hidden.
//
//  Note on coordinates: AppKit's screen origin is bottom-left, so the TOP edge of a screen
//  is `frame.maxY` and a top-anchored window's origin.y is `frame.maxY - windowHeight`.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class NotchWindowController: NSWindowController {

    private let viewModel: NotchViewModel
    private let settings: AppSettings
    private let hostingView: NotchHostingView

    /// Combine subscriptions (expand/collapse → tracking; geometry settings → reposition).
    private var cancellables = Set<AnyCancellable>()

    /// Notch size used on Macs without a hardware notch.
    private static let fallbackNotchSize = CGSize(width: 200, height: 32)

    /// Observer tokens. `nonisolated(unsafe)` because the nonisolated `deinit` reads them;
    /// they are written once in `init` and only read again in `deinit`, so there is no race.
    nonisolated(unsafe) private var appObservers: [NSObjectProtocol] = []
    nonisolated(unsafe) private var workspaceObservers: [NSObjectProtocol] = []
    /// NSWorkspace's centre, captured on the main actor so `deinit` needn't touch NSWorkspace.
    nonisolated(unsafe) private var workspaceCenter: NotificationCenter?

    /// Whether the window currently has the EXPANDED size (vs. the hover-zone size).
    private var windowIsExpandedSize = false
    /// Pending shrink back to the hover-zone size after the close animation.
    private var pendingShrink: Task<Void, Never>?
    /// App-lifetime poll that reconciles hover state with the real cursor position.
    private var hoverPoll: Task<Void, Never>?

    init(viewModel: NotchViewModel, settings: AppSettings) {
        self.viewModel = viewModel
        self.settings = settings

        let hosting = NotchHostingView(rootView: NotchView(viewModel: viewModel))
        // The SwiftUI content must never drive the window size: the window is resized only
        // by `positionWindow()` (geometry change, expand, or post-collapse shrink).
        hosting.sizingOptions = []
        self.hostingView = hosting

        let panel = NotchWindow(
            contentRect: NSRect(origin: .zero, size: viewModel.collapsedWindowSize),
            hostingView: hosting
        )

        super.init(window: panel)

        // Forward hover events from the hosting view's tracking area to the view model.
        hosting.onHoverChange = { [weak viewModel] isInside in
            viewModel?.hoverChanged(isInside)
        }

        // Lets delayed opens/closes re-check the REAL cursor position when they fire.
        viewModel.pointerInsideProvider = { [weak hosting] in
            hosting?.pointerIsInTrackedRect() ?? false
        }

        // Grow the window synchronously before opening; shrink after the close animation.
        viewModel.expansionWillChange = { [weak self] expanding in
            self?.expansionWillChange(expanding)
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
            // DispatchQueue.main (not RunLoop.main): RunLoop.main only delivers in the default
            // run-loop mode, so changes made while dragging a Settings slider would wait until
            // mouse-up. DispatchQueue.main also delivers during event tracking, so the window
            // and hover zone update live while dragging.
            .receive(on: DispatchQueue.main)
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
            // DispatchQueue.main (not RunLoop.main): RunLoop.main only delivers in the default
            // run-loop mode, so changes made while dragging a Settings slider would wait until
            // mouse-up. DispatchQueue.main also delivers during event tracking, so the window
            // and hover zone update live while dragging.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.positionWindow()
            }
            .store(in: &cancellables)

        // Observer blocks are @Sendable, so each only hops to the main actor.
        let center = NotificationCenter.default
        // Reposition (and re-show) when the display configuration changes.
        appObservers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.positionWindow()
                self?.ensureVisible()
            }
        })
        // Activation changes (Settings opening/closing, clicking other apps) must never leave
        // the notch panel hidden.
        for name in [NSApplication.didBecomeActiveNotification,
                     NSApplication.didResignActiveNotification] {
            appObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.ensureVisible()
                }
            })
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        self.workspaceCenter = workspaceCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.ensureVisible()
            }
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        for token in appObservers {
            NotificationCenter.default.removeObserver(token)
        }
        if let workspaceCenter {
            for token in workspaceObservers {
                workspaceCenter.removeObserver(token)
            }
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

        // 2. Size (depends on the measured notch through the hover size): the hover zone
        //    while collapsed, the full panel while expanded (or closing).
        let size = windowIsExpandedSize ? viewModel.windowSize : viewModel.collapsedWindowSize
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
        let hoverRect = Self.topCenteredRect(viewModel.hoverSize,
                                             topInset: CGFloat(settings.hoverVerticalOffset),
                                             in: hostingView)
        let hoverOnScreen = window.convertToScreen(hostingView.convert(hoverRect, to: nil))
        print("[AgoyNotch] screen.maxY=\(screenFrame.maxY) window.maxY=\(window.frame.maxY) "
              + "notch=\(notch) safeArea.top=\(screen?.safeAreaInsets.top ?? 0) "
              + "hosting.safeAreaInsets.top=\(hostingView.safeAreaInsets.top) "
              + "expandedSize=\(windowIsExpandedSize) frame=\(window.frame) "
              + "isVisible=\(window.isVisible) hoverOnScreen=\(hoverOnScreen)")
        #endif
    }

    /// Grows the window before opening (synchronously, so SwiftUI animates the morph inside
    /// the already-large window) and shrinks it back once the close animation has finished.
    private func expansionWillChange(_ expanding: Bool) {
        pendingShrink?.cancel()
        pendingShrink = nil
        if expanding {
            if !windowIsExpandedSize {
                windowIsExpandedSize = true
                positionWindow()
            }
            return
        }
        // Plain value captured before the Task.
        let duration = max(settings.animationDuration, 0) + 0.05
        let nanos = UInt64(duration * 1_000_000_000)
        pendingShrink = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled, let self, !self.viewModel.isExpanded else { return }
            self.pendingShrink = nil
            self.windowIsExpandedSize = false
            self.positionWindow()
        }
    }

    // MARK: - Visibility

    /// Orders the panel front (it must never stay hidden after an activation, Space or
    /// screen change) and re-syncs hover with the real cursor position.
    func ensureVisible() {
        guard let window else { return }
        window.orderFrontRegardless()
        hostingView.reconcileHover()
        #if DEBUG
        print("[AgoyNotch] ensureVisible isVisible=\(window.isVisible) frame=\(window.frame) "
              + "occluded=\(!window.occlusionState.contains(.visible))")
        #endif
    }

    /// Shows the panel, performs the initial placement and starts the hover poll.
    func show() {
        positionWindow()
        ensureVisible()
        if hoverPoll == nil {
            // Safety net against lost enter/exit events. `[weak self]`: the loop ends by
            // itself if the controller goes away, so deinit never has to touch it.
            hoverPoll = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    guard let self else { return }
                    self.hostingView.reconcileHover()
                }
            }
        }
    }
}
