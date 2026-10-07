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

    /// The EXPANDED NSWindow size: big enough for both the panel and the (possibly offset)
    /// hover zone, so the expanded tracking area always covers the whole panel. The window
    /// grows to this just before opening and shrinks back to `collapsedWindowSize` after
    /// the close animation (see NotchWindowController).
    var windowSize: CGSize {
        let panel = panelSize
        let hover = hoverSize
        return CGSize(
            width: max(panel.width, hover.width),
            height: max(panel.height, hover.height + CGFloat(settings.hoverVerticalOffset))
        )
    }

    /// The COLLAPSED NSWindow size: exactly the hover zone (plus its vertical offset from the
    /// screen top), so the hover-zone preview outline fits. While collapsed the window also
    /// ignores mouse events entirely (see NotchWindowController), so it never swallows
    /// clicks on menu-bar items beside the notch.
    var collapsedWindowSize: CGSize {
        let hover = hoverSize
        return CGSize(width: hover.width, height: hover.height + CGFloat(settings.hoverVerticalOffset))
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

    /// Reports whether the cursor is REALLY inside the active hover zone right now (screen
    /// coordinates). Set by the window controller; checked when a delayed open/close fires
    /// so the panel never opens or closes against the cursor's real position.
    var pointerInsideProvider: (() -> Bool)?

    /// Called synchronously just before `isExpanded` changes (with the new value), so the
    /// window controller can grow the window before the open animation starts.
    var expansionWillChange: ((Bool) -> Void)?

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

    // MARK: - Hover-zone preview

    /// True for a moment after a hover-zone setting changes, so NotchView can outline the
    /// (otherwise invisible) zone on screen while the user adjusts it.
    @Published var showsHoverZonePreview = false
    private var previewTask: Task<Void, Never>?

    /// Shows the hover-zone outline for 1.5 s (restarted by every call).
    func flashHoverZonePreview() {
        showsHoverZonePreview = true
        previewTask?.cancel()
        previewTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.showsHoverZonePreview = false
        }
    }

    // MARK: - Hover handling

    /// LEVEL-triggered hover input, called by the window controller on every mouse move,
    /// poll tick and geometry change with the REAL cursor position (screen coordinates).
    /// Idempotent, so calling it repeatedly with the same value is harmless:
    ///
    /// - Inside:  cancels any pending close; if collapsed with no pending open, opens now
    ///            (open delay 0) or after the delay.
    /// - Outside: cancels any pending open (leaving early = never opens); if expanded with
    ///            no pending close, closes now (close delay 0) or after the delay.
    ///
    /// Because it is level-triggered, a delayed open/close whose re-check fails just leaves
    /// `pending* == nil`, and the next call re-arms it — the state can never get stuck.
    func updateHover(isInside: Bool) {
        if isInside {
            pendingClose?.cancel()
            pendingClose = nil
            guard !isExpanded, pendingOpen == nil else { return }

            let delay = settings.openDelay
            if delay <= 0 {
                setExpanded(true)
                return
            }
            // Capture the delay as a plain value so the task needs `self` only after the
            // weak unwrap.
            let nanos = UInt64(delay * 1_000_000_000)
            pendingOpen = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled, let self else { return }
                self.pendingOpen = nil
                // The cursor left without a reliable exit event: don't open.
                guard self.pointerInsideProvider?() ?? true else { return }
                self.setExpanded(true)
            }
        } else {
            pendingOpen?.cancel()
            pendingOpen = nil
            // `pendingClose == nil` is essential: without it every tick would restart the
            // close timer and the panel would never close.
            guard isExpanded, pendingClose == nil else { return }

            let delay = settings.closeDelay
            if delay <= 0 {
                setExpanded(false)
                return
            }
            let nanos = UInt64(delay * 1_000_000_000)
            pendingClose = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: nanos)
                guard !Task.isCancelled, let self else { return }
                self.pendingClose = nil
                // The cursor is still on the panel (spurious exit): stay open.
                guard !(self.pointerInsideProvider?() ?? false) else { return }
                self.setExpanded(false)
            }
        }
    }

    /// True while `expansionWillChange` runs. Growing the window there re-evaluates hover
    /// (positionWindow → refreshTracking → updateHover) while `isExpanded` still has the old
    /// value; this flag makes that nested call a no-op instead of a second, nested open.
    private var isChangingExpansion = false

    /// The single place `isExpanded` is written.
    private func setExpanded(_ value: Bool) {
        guard isExpanded != value, !isChangingExpansion else { return }
        #if DEBUG
        print("[AgoyNotch] \(value ? "open" : "close")")
        #endif
        isChangingExpansion = true
        expansionWillChange?(value)
        isChangingExpansion = false
        isExpanded = value
    }
}
