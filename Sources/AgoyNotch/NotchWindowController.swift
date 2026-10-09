//
//  NotchWindowController.swift
//  AgoyNotch
//
//  Measures the hardware notch and places the overlay window so its TOP edge is the
//  physical top of the screen (`screen.frame.maxY`), centered on the notch. Repositions
//  live when a geometry setting changes or the display configuration changes.
//
//  Hover: decided HERE, in SCREEN coordinates, by comparing `NSEvent.mouseLocation` with
//  a hover zone computed from `screen.frame` and Settings (Width × Height, centred on the
//  notch plus the horizontal offset). The zone ALWAYS starts at the very top of the screen
//  (reaching `topSlop` above it) and extends DOWN by Height; no setting can move its top,
//  so a cursor pinned to the very top row is always inside. While the music activity pill
//  is visible, the pill's area counts as hover too. It never depends on the window bounds,
//  event locations or tracking-area rebuilds. The containment test is inclusive. Evaluation is
//  LEVEL-triggered (NotchViewModel.updateHover is idempotent) and runs on every mouse move
//  (global + local monitors), on a poll (safety net for a stationary cursor), on
//  tracking-area enter/exit (fast path while expanded), on expand/collapse, geometry
//  changes and ensureVisible().
//
//  Clicks: while COLLAPSED the window ignores mouse events entirely, so it never swallows
//  clicks on menu-bar items beside the notch; mouse events are turned on just before the
//  panel expands (so the buttons work) and off again as soon as it starts to collapse.
//
//  Window size: while COLLAPSED the window is the hover-zone size, or max(hover zone, music
//  pill) when the music activity is enabled (room for the hover-zone outline and the pill;
//  it does not change on play/pause). Just before the panel opens it grows to the expanded size; after the
//  close animation it shrinks back. The grow-out-of-the-notch morph itself is pure SwiftUI
//  inside the window (see NotchView).
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

    /// How far the hover zone reaches ABOVE the screen top. `NSEvent.mouseLocation.y` can be
    /// exactly `screen.frame.maxY` on the top row, so the zone must include that edge.
    private static let topSlop: CGFloat = 3

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
    /// App-lifetime poll that re-evaluates hover for a stationary cursor.
    private var hoverPoll: Task<Void, Never>?
    /// NSEvent mouse-moved monitors (global + local). Main-actor state, deliberately NOT
    /// removed in `deinit`: the controller lives for the whole app and the handlers capture
    /// `self` weakly, so they become no-ops if it ever goes away.
    private var mouseMonitors: [Any] = []
    /// The frame of the screen the window was last placed on (screen coordinates).
    private var screenFrame: CGRect?
    #if DEBUG
    private var lastLoggedInside: Bool?
    #endif

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

        // Tracking-area enter/exit (and tracking rebuilds) just trigger a screen-space
        // re-evaluation; they carry no inside/outside value of their own.
        hosting.onPointerEvent = { [weak self] in
            self?.evaluateHover()
        }

        // Interaction hold: while a click inside the expanded panel is in progress (and for a
        // short grace window after it), the hover-driven CLOSE is suppressed so the click is
        // delivered without the panel collapsing underneath it. The intended badge / Now
        // Playing close still happens via collapseNow() in their tap handlers.
        hosting.onInteractionBegan = { [weak viewModel] in
            viewModel?.beginInteraction()
        }
        hosting.onInteractionEnded = { [weak viewModel] in
            viewModel?.endInteraction()
        }

        // Lets delayed opens/closes re-check the REAL cursor position when they fire.
        viewModel.pointerInsideProvider = { [weak self] in
            self?.pointerIsInActiveZone() ?? false
        }

        // Grow the window synchronously before opening; shrink after the close animation.
        viewModel.expansionWillChange = { [weak self] expanding in
            self?.expansionWillChange(expanding)
        }

        // Tracking-area rect (fast path only; it fires while the window accepts mouse
        // events, i.e. while expanded):
        //  • COLLAPSED → the hover zone over the notch (Settings → Hover area), plus the
        //    music pill while it is visible.
        //  • EXPANDED  → the whole panel (plus the hover zone, in case it is wider than the
        //    panel), so moving onto the transport buttons is noticed immediately.
        hosting.trackingRectProvider = { [weak viewModel, weak hosting] in
            guard let viewModel, let hosting else { return nil }
            var hoverRect = Self.topCenteredRect(viewModel.hoverSize, in: hosting)
            if viewModel.showsMusicActivity {
                hoverRect = hoverRect.union(Self.topCenteredRect(viewModel.musicActivitySize, in: hosting))
            }
            guard viewModel.isExpanded else { return hoverRect }
            return Self.topCenteredRect(viewModel.panelSize, in: hosting).union(hoverRect)
        }

        // CLICK rect: nothing while collapsed (clicks pass through), the panel while expanded.
        hosting.interactiveRectProvider = { [weak viewModel, weak hosting] in
            guard let viewModel, let hosting else { return nil }
            guard viewModel.isExpanded else { return .zero }
            return Self.topCenteredRect(viewModel.panelSize, in: hosting)
        }

        // Swap the tracked rect between hover zone and panel on every expand/collapse
        // (refreshTracking also re-evaluates hover via onPointerEvent).
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
            // Changes collapsedWindowSize (max(hover, pill) vs. hover only).
            settings.$showMusicActivity.map { _ in () }.eraseToAnyPublisher(),
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

        // Outline the hover zone for a moment whenever its size or position changes, so the
        // user can SEE the effect of the sliders. `dropFirst()` skips the replay on subscribe.
        let hoverZoneChanges: [AnyPublisher<Void, Never>] = [
            settings.$hoverWidth.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$hoverHeight.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$horizontalOffset.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(hoverZoneChanges)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.viewModel.flashHoverZonePreview()
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
        // mouseMonitors: intentionally not touched (main-actor state; see its declaration).
    }

    // MARK: - Geometry

    /// A `size` rect, horizontally centered and hugging the TOP edge of the hosting view,
    /// in the hosting view's coordinates. Handles both flipped and non-flipped hosting
    /// views. Used only for the tracking area (fast path) and the click rect — hover itself
    /// is decided in screen space.
    private static func topCenteredRect(_ size: CGSize, in hosting: NotchHostingView) -> CGRect {
        let full = hosting.bounds
        let w = min(size.width, full.width)
        let h = min(size.height, full.height)
        let x = full.midX - w / 2
        let y = hosting.isFlipped ? full.minY : full.maxY - h
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

    // MARK: - Screen-space hover zone

    private func currentScreenFrame() -> CGRect? {
        screenFrame ?? notchScreen()?.frame
    }

    /// The configured hover zone in SCREEN coordinates: exactly Settings Width × Height,
    /// centred on the notch (`screen.midX + horizontalOffset`). Its top is ALWAYS the very
    /// top of the screen plus `topSlop` — whatever the settings — and it extends DOWN by
    /// Height, so a cursor resting on the top row (`mouseLocation.y == sf.maxY`) is inside.
    private func configuredHoverZoneOnScreen() -> CGRect? {
        guard let sf = currentScreenFrame() else { return nil }
        let s = viewModel.hoverSize
        let cx = sf.midX + CGFloat(settings.horizontalOffset)
        return CGRect(x: cx - s.width / 2, y: sf.maxY - s.height,
                      width: s.width, height: s.height + Self.topSlop)
    }

    /// The visible music activity pill in SCREEN coordinates (plus `topSlop` above the
    /// screen top), or nil while it is not shown (disabled, or Apple Music not playing).
    private func musicActivityZoneOnScreen() -> CGRect? {
        guard viewModel.showsMusicActivity, let sf = currentScreenFrame() else { return nil }
        let s = viewModel.musicActivitySize
        let cx = sf.midX + CGFloat(settings.horizontalOffset)
        return CGRect(x: cx - s.width / 2, y: sf.maxY - s.height,
                      width: s.width, height: s.height + Self.topSlop)
    }

    /// The COLLAPSED hover zone: the configured zone, united with the music pill while the
    /// pill is visible. Design choice: hovering the pill (artwork or equalizer) opens the
    /// panel, as in NotchNook. Trade-off: while music plays, menu-bar items under a wing
    /// (≈ notch height + 8 pt each side) also open the panel.
    func hoverZoneOnScreen() -> CGRect? {
        guard let configured = configuredHoverZoneOnScreen() else { return nil }
        guard let pill = musicActivityZoneOnScreen() else { return configured }
        return configured.union(pill)
    }

    /// The EXPANDED zone in SCREEN coordinates: the whole panel (from `topSlop` above the
    /// screen top down to the panel bottom) plus the hover zone, so the cursor can travel
    /// onto the transport buttons without closing the panel.
    func panelZoneOnScreen() -> CGRect? {
        guard let sf = currentScreenFrame(), let hover = hoverZoneOnScreen() else { return nil }
        let p = viewModel.panelSize
        let cx = sf.midX + CGFloat(settings.horizontalOffset)
        let panel = CGRect(x: cx - p.width / 2, y: sf.maxY - p.height,
                           width: p.width, height: p.height + Self.topSlop)
        return panel.union(hover)
    }

    /// Whether the REAL cursor is inside the zone that matters right now (hover zone while
    /// collapsed, panel ∪ hover zone while expanded). INCLUSIVE on every edge — unlike
    /// CGRect.contains / NSPointInRect, which treat maxX/maxY as outside.
    func pointerIsInActiveZone() -> Bool {
        let zone = viewModel.isExpanded ? panelZoneOnScreen() : hoverZoneOnScreen()
        guard let zone else { return false }
        let p = NSEvent.mouseLocation
        return p.x >= zone.minX && p.x <= zone.maxX && p.y >= zone.minY && p.y <= zone.maxY
    }

    /// Level-triggered hover evaluation; cheap and idempotent, safe to call at any time.
    func evaluateHover() {
        let inside = pointerIsInActiveZone()
        #if DEBUG
        if inside != lastLoggedInside {
            lastLoggedInside = inside
            let zone = viewModel.isExpanded ? panelZoneOnScreen() : hoverZoneOnScreen()
            print("[AgoyNotch] hover inside=\(inside) expanded=\(viewModel.isExpanded) "
                  + "zone=\(String(describing: zone)) mouse=\(NSEvent.mouseLocation)")
        }
        #endif
        viewModel.updateHover(isInside: inside)
    }

    /// Whether the cursor is near the top of the screen (poll quickly there, slowly
    /// elsewhere — the mouse-moved monitors cover moves anyway).
    private func pointerIsNearTop() -> Bool {
        guard let sf = currentScreenFrame() else { return true }
        let p = NSEvent.mouseLocation
        return p.y >= sf.maxY - 150 && p.x >= sf.minX && p.x <= sf.maxX
    }

    // MARK: - Placement

    /// Sizes and places the window: top edge at `screen.frame.maxY` (the physical top of
    /// the display — `frame`, never `visibleFrame`, which stops below the menu bar),
    /// centered on the notch plus the horizontal offset. There is deliberately no vertical
    /// offset for the window: moving it down would re-create the gap under the notch.
    func positionWindow() {
        guard let window else { return }
        let screen = notchScreen()
        screenFrame = screen?.frame

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
            // Re-evaluate on this path too, so a Width/Height change always takes effect.
            evaluateHover()
            return
        }

        // 3. Place: top edge = screen top. NotchWindow.constrainFrameRect keeps AppKit from
        //    pushing it below the menu bar.
        let originX = screenFrame.midX - size.width / 2 + CGFloat(settings.horizontalOffset)
        let originY = screenFrame.maxY - size.height
        window.setFrame(NSRect(x: originX, y: originY, width: size.width, height: size.height),
                        display: true)

        // 4. The tracking rects may have changed; this also re-evaluates hover against the
        //    NEW screen-space zone (so a resized zone takes effect without moving the cursor).
        hostingView.refreshTracking()

        #if DEBUG
        print("[AgoyNotch] screen.maxY=\(screenFrame.maxY) window.maxY=\(window.frame.maxY) "
              + "notch=\(notch) safeArea.top=\(screen?.safeAreaInsets.top ?? 0) "
              + "hosting.safeAreaInsets.top=\(hostingView.safeAreaInsets.top) "
              + "expandedSize=\(windowIsExpandedSize) frame=\(window.frame) "
              + "isVisible=\(window.isVisible) "
              + "hoverZoneOnScreen=\(String(describing: hoverZoneOnScreen()))")
        #endif
    }

    /// Grows the window before opening (synchronously, so SwiftUI animates the morph inside
    /// the already-large window) and shrinks it back once the close animation has finished.
    /// Also toggles click-through: interactive only while expanded.
    private func expansionWillChange(_ expanding: Bool) {
        pendingShrink?.cancel()
        pendingShrink = nil
        if expanding {
            window?.ignoresMouseEvents = false
            if !windowIsExpandedSize {
                windowIsExpandedSize = true
                positionWindow()
            }
            // Become key so the panel actually receives the first mouse-DOWN: a borderless,
            // never-key panel at this high level drops clicks, so SwiftUI Buttons / taps
            // inside never fire. `.nonactivatingPanel` means becoming key does NOT activate
            // the app or steal focus from the user's foreground app.
            window?.makeKeyAndOrderFront(nil)
            return
        }
        // Collapsing: give clicks back to the menu bar immediately.
        window?.ignoresMouseEvents = true
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
    /// screen change) and re-evaluates hover with the real cursor position.
    func ensureVisible() {
        guard let window else { return }
        window.orderFrontRegardless()
        evaluateHover()
        #if DEBUG
        print("[AgoyNotch] ensureVisible isVisible=\(window.isVisible) frame=\(window.frame) "
              + "occluded=\(!window.occlusionState.contains(.visible)) "
              + "ignoresMouseEvents=\(window.ignoresMouseEvents)")
        #endif
    }

    /// Shows the panel, performs the initial placement, installs the mouse-moved monitors
    /// and starts the hover poll.
    func show() {
        positionWindow()
        ensureVisible()
        if mouseMonitors.isEmpty {
            // Mouse-moved monitors need no Accessibility permission. Global: moves while
            // another app is under the cursor; local: moves delivered to this app.
            if let global = NSEvent.addGlobalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged],
                handler: { [weak self] _ in
                    Task { @MainActor in
                        self?.evaluateHover()
                    }
                }
            ) {
                mouseMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(
                matching: [.mouseMoved, .leftMouseDragged],
                handler: { [weak self] event in
                    Task { @MainActor in
                        self?.evaluateHover()
                    }
                    return event
                }
            ) {
                mouseMonitors.append(local)
            }
        }
        if hoverPoll == nil {
            // Safety net for a cursor that rests without moving (e.g. pinned at the top row
            // while the zone changes). 100 ms near the top of the screen or while expanded,
            // 500 ms elsewhere. `[weak self]`: the loop ends by itself if the controller goes
            // away, so deinit never has to touch it.
            hoverPoll = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    let fast = self.map { $0.viewModel.isExpanded || $0.pointerIsNearTop() } ?? false
                    try? await Task.sleep(nanoseconds: fast ? 100_000_000 : 500_000_000)
                    guard let self else { return }
                    self.evaluateHover()
                }
            }
        }
    }
}
