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
import Combine
import SwiftUI

final class NotchWindowController: NSWindowController {

    private let viewModel: NotchViewModel
    private let hostingView: NotchHostingView

    /// Combine subscriptions (currently the `isExpanded` observation that rebuilds the
    /// hover tracking area). Held so they stay alive for the controller's lifetime.
    private var cancellables = Set<AnyCancellable>()

    /// User fine-tuning (horizontal/vertical offset + width/height adjustment) layered on
    /// top of the auto-detected notch geometry. Loaded from UserDefaults; updated live from
    /// the menu-bar "Adjust Notch" commands via `applySettings(_:)`.
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

        // DRAWING / CLICKS ↔ HOVER are DECOUPLED. The window is permanently the expanded
        // size; the hosting view uses two independent providers:
        //   • `trackingRectProvider`  → where the NSTrackingArea listens for hover.
        //   • `interactiveRectProvider`→ where `hitTest` swallows clicks (else they pass
        //                                 through to the desktop / menu bar / other apps).
        // NSTrackingArea and hitTest are independent in AppKit, so hover can fire at points
        // where hitTest returns `nil`. We exploit that: while collapsed the overlay paints
        // NOTHING and swallows NO clicks, yet it still TRACKS hover over the physical notch.
        //
        // (See `topCenteredRect(width:height:in:)` for the shared geometry helper.)
        //
        // HOVER-TRACKING rect. This geometry is UNCHANGED from before and is what keeps both
        // prior hover bugs fixed:
        //  • COLLAPSED → the small notch-sized rect at the top center (NOT the whole
        //    window). Entering the real notch fires `mouseEntered`; the cursor anywhere else
        //    over the big transparent window does NOT expand (phantom-expand fix). The rect
        //    stays here EVEN THOUGH collapsed now paints nothing — hover is decoupled from
        //    drawing.
        //  • EXPANDED → the shape is pushed DOWN by `notchInset`, so the tracked region
        //    spans notchInset + expandedSize.height, letting the cursor travel from the
        //    notch onto the transport buttons without leaving the region (move-to-buttons
        //    fix).
        hosting.trackingRectProvider = { [weak viewModel, weak hosting] in
            guard let viewModel, let hosting else { return nil }
            if viewModel.isExpanded {
                return Self.topCenteredRect(
                    width: viewModel.expandedSize.width,
                    height: viewModel.notchInset + viewModel.expandedSize.height,
                    in: hosting
                )
            } else {
                return Self.topCenteredRect(
                    width: viewModel.collapsedSize.width,
                    height: viewModel.collapsedSize.height,
                    in: hosting
                )
            }
        }

        // CLICK HIT-TEST rect — independent of the tracking rect above.
        //  • COLLAPSED → `.zero` (empty). The overlay paints nothing, so clicks over the
        //    invisible notch region pass straight through (`hitTest` returns `nil`). Hover
        //    still works because it uses `trackingRectProvider`, not this.
        //  • EXPANDED → the full dropped panel, so clicks hit the transport buttons.
        hosting.interactiveRectProvider = { [weak viewModel, weak hosting] in
            guard let viewModel, let hosting else { return nil }
            guard viewModel.isExpanded else {
                return .zero // collapsed paints nothing → swallow no clicks (pass through)
            }
            return Self.topCenteredRect(
                width: viewModel.expandedSize.width,
                height: viewModel.notchInset + viewModel.expandedSize.height,
                in: hosting
            )
        }

        // Rebuild the hover tracking area whenever the panel toggles between collapsed and
        // expanded. The tracked rect follows the interactive region: the small pill over the
        // notch while collapsed, the full dropped panel while expanded (see
        // `NotchHostingView.updateTrackingAreas`). Without this the collapsed tracking rect
        // would never grow and the cursor would leave it as soon as the panel expanded.
        //
        // `viewModel` is @MainActor and `$isExpanded` publishes on the main actor (it is
        // only mutated there), and `receive(on:)` guarantees the AppKit call runs on main.
        // `[weak hosting]` avoids a retain cycle (the controller owns `hosting`, which — via
        // its providers — would otherwise capture the controller/view model strongly).
        viewModel.$isExpanded
            .receive(on: RunLoop.main)
            .sink { [weak hosting] _ in
                hosting?.refreshTracking()
            }
            .store(in: &cancellables)

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

    /// The top-centered rect, in the hosting view's coordinate space, that spans the given
    /// on-screen `width` × `height`. The hosting view is NOT flipped (AppKit default origin
    /// bottom-left) while the SwiftUI content is drawn top-anchored, so the rect hugs the
    /// TOP edge; we pick `maxY`/`minY` by `isFlipped` to stay correct regardless of
    /// NSHostingView's flip convention. Shared by the tracking- and hit-test-rect providers.
    private static func topCenteredRect(width: CGFloat,
                                        height: CGFloat,
                                        in hosting: NotchHostingView) -> CGRect {
        let full = hosting.bounds
        let w = min(width, full.width)
        let h = min(height, full.height)
        let x = full.midX - w / 2
        let y = hosting.isFlipped ? full.minY : full.maxY - h
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Finds the screen with a hardware notch, or falls back to the main screen.
    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Measures the collapsed pill size from the notch geometry (or fallback), then applies
    /// the user's `widthAdjustment` and `heightAdjustment` on top. Both dimensions are
    /// clamped to a small positive minimum so over-aggressive "Narrower"/"Shorter" cannot
    /// collapse the shape to zero/negative size.
    ///
    /// Width comes from the gap between the two auxiliary top areas (the physical notch
    /// width); we add a little slack so a small music glyph fits just LEFT of the notch and
    /// the equalizer just RIGHT of it, so the collapsed shape hugs the notch while leaving
    /// room for the two indicators. Height comes from `safeAreaInsets.top` (the notch
    /// height / menu-bar strip) so the black shape coincides with the real notch's height
    /// instead of adding a second shape beneath it.
    private func measuredCollapsedSize(for screen: NSScreen?) -> CGSize {
        // Extra width (points) added to the bare notch width. Kept SMALL so the collapsed
        // shape overlays the physical notch rather than forming a wider black bar beneath
        // it (the "strip below the notch" look the user complained about). The glyph and
        // equalizer live just inside the left/right of this near-notch-width shape. Tunable
        // via the Wider/Narrower menu for the user's exact hardware (default ~8pt slack).
        let indicatorSlack: CGFloat = 8

        let base: CGSize
        if let screen, screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            // Notch width = full screen width minus the usable areas either side of it.
            let notchWidth = screen.frame.width - left - right
            let notchHeight = screen.safeAreaInsets.top
            // Guard against degenerate measurements.
            base = (notchWidth > 0 && notchHeight > 0)
                ? CGSize(width: notchWidth + indicatorSlack, height: notchHeight)
                : fallbackCollapsedSize
        } else {
            base = fallbackCollapsedSize
        }

        let adjustedWidth = max(1, base.width + settings.widthAdjustment)
        // heightAdjustment lets the user make the collapsed black shape exactly cover their
        // real notch's vertical extent when safeAreaInsets.top is a hair off.
        let adjustedHeight = max(1, base.height + settings.heightAdjustment)
        return CGSize(width: adjustedWidth, height: adjustedHeight)
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
        // pinned to the TOP edge of the screen (maxY in AppKit's bottom-left coordinate
        // space; a top-anchored window of height H therefore has origin.y = maxY - H).
        // Because the window is the expanded width, centering it on the notch also centers
        // the collapsed shape (which SwiftUI draws top-centered inside the window), and
        // because the window top is exactly screen-top, the top-anchored collapsed shape's
        // top edge lands at the physical top of the display — flush over the hardware notch
        // rather than below it.
        //
        // Default offsets are all 0 (see NotchSettings) precisely so this auto-detected
        // placement already sits the collapsed shape ON the notch; the user only needs tiny
        // Move/Wider/Taller nudges to perfect the seam on their specific hardware.
        var originX = screenFrame.midX - size.width / 2
        var originY = screenFrame.maxY - size.height

        // Layer the user's manual adjustments on top of the auto-detected placement.
        //  • horizontalOffset: positive moves the overlay right, so add directly to X.
        //  • verticalOffset: positive nudges the overlay DOWN. Because AppKit's origin is
        //    bottom-left, moving down means DECREASING originY, so we subtract it.
        // These shift the WHOLE fixed-size overlay so it lines up with the real notch;
        // width/heightAdjustment are handled separately in `measuredCollapsedSize` (they
        // tune the drawn collapsed shape, and heightAdjustment also feeds the notch inset /
        // window height via viewModel.windowSize — which is why updateCollapsedSize above
        // runs before we read `size`).
        originX += settings.horizontalOffset
        originY -= settings.verticalOffset

        let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        // Never animate the frame: the window size is constant, so there is nothing to
        // animate here. The collapsed↔expanded morph is a SwiftUI spring inside the window.
        window.setFrame(frame, display: true, animate: false)

        // The collapsed size may have changed above (measurement or a Wider/Taller nudge),
        // which changes the collapsed interactive rect. Rebuild the hover tracking area so
        // the tracked pill matches the newly drawn collapsed shape.
        hostingView.refreshTracking()
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
