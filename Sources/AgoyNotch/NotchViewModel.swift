//
//  NotchViewModel.swift
//  AgoyNotch
//
//  UI state for the notch surface: collapsed vs. expanded, hover handling with a short
//  open/close debounce, and the collapsed/expanded panel sizes the window controller needs.
//  Holds the NowPlayingManager so the SwiftUI view can observe media through the view model.
//

import AppKit
import Combine

/// Observable UI state driving the notch overlay.
///
/// Main-actor-isolated: it is a UI `ObservableObject` and it holds the main-actor-isolated
/// `NowPlayingManager`, so keeping the view model on the main actor lets it construct the
/// manager, subscribe to its `objectWillChange`, and (indirectly, through `NotchView`)
/// drive its transport methods without any cross-actor hops. All call sites —
/// `AppDelegate`'s launch delegate method and `NotchWindowController` (both AppKit
/// `@MainActor`) — already run on the main actor.
@MainActor
final class NotchViewModel: ObservableObject {

    /// Whether the panel is currently expanded into the Now Playing panel.
    @Published var isExpanded: Bool = false

    /// The media service, exposed so `NotchView` can observe it.
    let nowPlaying: NowPlayingManager

    // MARK: - Timing / layout constants

    /// Delay before collapsing after the cursor leaves the notch region. Prevents the
    /// panel from flickering shut when the cursor briefly crosses an edge.
    private let collapseDebounce: TimeInterval = 0.35

    /// Collapsed pill size. Width/height are supplied by the window controller from the
    /// measured notch geometry (safeAreaInsets.top for height, the gap between the two
    /// auxiliary top areas for width) plus the user's width/height adjustments, via
    /// `updateCollapsedSize(_:)`; these are only fallbacks.
    ///
    /// This drives the SwiftUI collapsed shape drawn TOP-ANCHORED inside the fixed window
    /// so its top edge sits at the physical top of the screen and it coincides with the
    /// real hardware notch (height ≈ notch height) rather than hanging below it. The WINDOW
    /// itself is always `windowSize` (see below), never the collapsed size.
    private(set) var collapsedSize = CGSize(width: 200, height: 32)

    /// Expanded Now Playing panel size (points). Sized toward the NotchNook ballpark
    /// (~460–520 wide, ~220–260 tall) so the panel that drops out of the notch feels like
    /// NotchNook rather than a thin strip, with comfortable room for the album art, the
    /// title/album/artist stack, and the transport controls BELOW the notch-width top band.
    let expandedSize = CGSize(width: 480, height: 240)

    /// Height of the panel's notch-width TOP BAND, i.e. the strip at the very top of the
    /// expanded panel that is as wide as the hardware notch and sits directly beneath it.
    /// The expanded panel's content is inset below this band so nothing is hidden behind the
    /// physical notch cutout, and `NotchPanelShape` uses it as the height of the flat-topped
    /// band before the shape flares out to full width. Mirrors the measured notch height.
    var notchInset: CGFloat { collapsedSize.height }

    /// The fixed on-screen size of the NSWindow — ALWAYS the full expanded panel size,
    /// regardless of `isExpanded`. The expanded panel is drawn flush at the TOP of this
    /// window (its top band fused with the hardware notch) and grows DOWN/OUT inside it; the
    /// window top is pinned to the physical top of the display (see NotchWindowController),
    /// so there is no gap above the panel.
    ///
    /// This is the heart of the hover-collapse bug fix: the window never resizes when the
    /// panel expands or collapses. Because the window (and therefore the hosting view's
    /// tracking area) is permanently as large as the full expanded panel, the cursor can
    /// travel from the notch down onto the transport buttons without ever leaving the
    /// tracked region — so no spurious `mouseExited` fires and the panel stays open. The
    /// SwiftUI content simply paints either NOTHING (collapsed) or the full expanded panel
    /// (grown out of the notch) inside this fixed frame; the surrounding area is transparent.
    var windowSize: CGSize { expandedSize }

    // MARK: - Private

    /// Pending collapse task, cancelled whenever the cursor re-enters. A `Task` (rather than
    /// a `DispatchWorkItem`) keeps the delayed body main-actor-isolated, so mutating
    /// `isExpanded` from it is race-free under strict concurrency.
    private var pendingCollapse: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(nowPlaying: NowPlayingManager) {
        self.nowPlaying = nowPlaying

        // Re-broadcast the media service's changes through this view model so a single
        // @ObservedObject in the view updates for both state and media changes.
        nowPlaying.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Geometry

    /// Called by the window controller once the real notch size is measured.
    func updateCollapsedSize(_ size: CGSize) {
        collapsedSize = size
        // Nudge observers so the view resizes while collapsed.
        objectWillChange.send()
    }

    // MARK: - Hover handling

    /// Forwarded from the window's tracking area. Entering expands immediately; leaving
    /// collapses after a short debounce.
    func hoverChanged(_ isInside: Bool) {
        if isInside {
            pendingCollapse?.cancel()
            pendingCollapse = nil
            if !isExpanded {
                // Already main-actor-isolated, so mutate directly. The spring animation is
                // applied in the SwiftUI view via `.animation(_:value:)`.
                isExpanded = true
            }
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        pendingCollapse?.cancel()
        // Capture the delay as a plain value so the task body does not need `self` before
        // the weak-self unwrap below.
        let debounceNanos = UInt64(collapseDebounce * 1_000_000_000)
        pendingCollapse = Task { @MainActor [weak self] in
            // Debounce the collapse. If the cursor re-enters, `hoverChanged` cancels this
            // task before the sleep returns and we bail out.
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled, let self else { return }
            self.isExpanded = false
            self.pendingCollapse = nil
        }
    }
}
