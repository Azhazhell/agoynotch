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
    /// measured notch geometry via `updateCollapsedSize(_:)`; these are only fallbacks.
    private(set) var collapsedSize = CGSize(width: 200, height: 32)

    /// Expanded Now Playing panel size (points).
    let expandedSize = CGSize(width: 360, height: 120)

    /// The size the window should currently be, based on `isExpanded`.
    var currentSize: CGSize { isExpanded ? expandedSize : collapsedSize }

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
