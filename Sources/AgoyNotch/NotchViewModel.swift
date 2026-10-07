//
//  NotchViewModel.swift
//  AgoyNotch
//
//  UI state for the notch surface: collapsed vs. expanded, the hover state machine (open
//  delay / close delay, each cancellable), and the sizes the view and window controller
//  need — all derived live from AppSettings. Holds the NowPlayingManager so the SwiftUI
//  view can observe media through the view model.
//

import AppKit
import Combine

/// Observable UI state driving the notch overlay.
///
/// Main-actor-isolated: it is a UI `ObservableObject` holding the main-actor-isolated
/// `NowPlayingManager` and `AppSettings`. All call sites (AppDelegate, the window
/// controller, the hosting view's tracking callbacks) already run on the main actor.
@MainActor
final class NotchViewModel: ObservableObject {

    /// Whether the panel is currently expanded.
    @Published var isExpanded: Bool = false

    /// The media service, exposed so `NotchView` can observe it.
    let nowPlaying: NowPlayingManager

    /// User settings (delays, animation, geometry). Read at the moment they are used, so
    /// changes made in the Settings window apply immediately.
    let settings: AppSettings

    // MARK: - Geometry (all derived from settings)

    /// The hardware notch size, measured by NotchWindowController.
    var notchSize: CGSize { settings.measuredNotchSize }

    /// The collapsed hover zone over the notch.
    var hoverSize: CGSize { settings.effectiveHoverSize }

    /// The expanded panel. Its top edge is the very top of the screen, so its height
    /// includes the band that covers the hardware notch.
    var panelSize: CGSize { CGSize(width: settings.panelWidth, height: settings.panelHeight) }

    /// The fixed NSWindow size: big enough for both the panel and the (possibly offset)
    /// hover zone. The window never resizes on expand/collapse — only when a geometry
    /// setting changes — so the expanded tracking area always covers the whole panel.
    var windowSize: CGSize {
        let panel = panelSize
        let hover = hoverSize
        return CGSize(
            width: max(panel.width, hover.width),
            height: max(panel.height, hover.height + CGFloat(settings.hoverVerticalOffset))
        )
    }

    /// Top padding for the panel CONTENT (inside the black shape) so album art, text,
    /// buttons and the clock sit just below the camera cutout instead of behind it.
    var contentTopInset: CGFloat { notchSize.height + 8 }

    // MARK: - Private

    /// Pending delayed open / close. `Task`s (not `DispatchWorkItem`s) keep the delayed body
    /// main-actor-isolated, so mutating `isExpanded` from it is race-free.
    private var pendingOpen: Task<Void, Never>?
    private var pendingClose: Task<Void, Never>?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(nowPlaying: NowPlayingManager, settings: AppSettings) {
        self.nowPlaying = nowPlaying
        self.settings = settings

        // Re-broadcast media and settings changes through this view model so a single
        // @ObservedObject in the view updates for state, media and settings changes.
        nowPlaying.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Hover handling

    /// Forwarded from the window's tracking area.
    ///
    /// - Enter: cancels any pending close; opens now (open delay 0) or after the delay.
    /// - Exit:  cancels any pending open (leaving early = never opens); closes now (close
    ///          delay 0) or after the delay.
    func hoverChanged(_ isInside: Bool) {
        if isInside {
            pendingClose?.cancel()
            pendingClose = nil
            guard !isExpanded, pendingOpen == nil else { return }

            let delay = settings.openDelay
            if delay <= 0 {
                isExpanded = true
                return
            }
            // Capture the delay as a plain value so the task needs `self` only after the
            // weak unwrap.
            let nanos = UInt64(delay * 1_000_000_000)
            pendingOpen = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled, let self else { return }
                self.pendingOpen = nil
                self.isExpanded = true
            }
        } else {
            pendingOpen?.cancel()
            pendingOpen = nil
            guard isExpanded else { return }

            let delay = settings.closeDelay
            if delay <= 0 {
                pendingClose?.cancel()
                pendingClose = nil
                isExpanded = false
                return
            }
            pendingClose?.cancel()
            let nanos = UInt64(delay * 1_000_000_000)
            pendingClose = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled, let self else { return }
                self.pendingClose = nil
                self.isExpanded = false
            }
        }
    }
}
