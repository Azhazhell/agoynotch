//
//  NotchViewModel.swift
//  AgoyNotch
//
//  UI state for the notch surface: collapsed vs. expanded, the hover state machine (open
//  delay / close delay, each cancellable), and the sizes the view and window controller
//  need — all derived live from AppSettings. Holds the NowPlayingManager and the
//  MessageBadgeMonitor so the SwiftUI view can observe media and badges through the view model.
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

    /// Messages / WhatsApp unread badges for the open panel.
    let messageBadges: MessageBadgeMonitor

    // MARK: - Geometry (all derived from settings)

    /// The hardware notch size, measured by NotchWindowController.
    var notchSize: CGSize { settings.measuredNotchSize }

    /// The collapsed hover zone over the notch.
    var hoverSize: CGSize { settings.effectiveHoverSize }

    /// The expanded panel. Its top edge is the very top of the screen, so its height
    /// includes the band that covers the hardware notch.
    var panelSize: CGSize { CGSize(width: settings.panelWidth, height: settings.panelHeight) }

    /// The EXPANDED NSWindow size: big enough for the panel, the hover zone (both start at
    /// the screen top) and — when the music activity is enabled — the pill, so neither the
    /// expanded tracking area nor the panel → pill collapse morph is ever clipped. The window
    /// grows to this just before opening and shrinks back to `collapsedWindowSize` after
    /// the close animation (see NotchWindowController).
    var windowSize: CGSize {
        let panel = panelSize
        let hover = hoverSize
        var size = CGSize(width: max(panel.width, hover.width), height: max(panel.height, hover.height))
        if settings.showMusicActivity {
            let pill = musicActivitySize
            size.width = max(size.width, pill.width)
            size.height = max(size.height, pill.height)
        }
        return size
    }

    /// The COLLAPSED NSWindow size: at least the hover zone, so the hover-zone outline fits.
    /// When the music activity is enabled it is ALWAYS `max(hover, pill)` per dimension,
    /// whether or not music is playing right now: the window is transparent and ignores
    /// mouse events while collapsed (see NotchWindowController), so the extra size costs
    /// nothing, and this avoids resizing the window on every play/pause or clipping the
    /// pill's fade-out. With the toggle off it is exactly the hover zone.
    var collapsedWindowSize: CGSize {
        let hover = hoverSize
        guard settings.showMusicActivity else { return hover }
        let pill = musicActivitySize
        return CGSize(width: max(hover.width, pill.width), height: max(hover.height, pill.height))
    }

    // MARK: - Music activity pill (collapsed, Apple Music playing)

    /// Extra width of each pill wing beyond the notch height (tunable).
    static let musicWingExtra: CGFloat = 8

    /// Width of each wing beside the notch (artwork on the left, equalizer on the right).
    var musicWingWidth: CGFloat { notchSize.height + Self.musicWingExtra }

    /// The collapsed pill: the notch plus a wing on each side, exactly the notch's height.
    var musicActivitySize: CGSize {
        CGSize(width: notchSize.width + 2 * musicWingWidth, height: notchSize.height)
    }

    /// Whether the pill is on (enabled in Settings AND Apple Music is playing). The view
    /// additionally hides it while expanded.
    var showsMusicActivity: Bool { settings.showMusicActivity && nowPlaying.info.isPlaying }

    /// Top padding for the panel CONTENT (inside the black shape) so album art, text,
    /// buttons and the clock sit just below the camera cutout instead of behind it.
    var contentTopInset: CGFloat { notchSize.height + 8 }

    /// Width of the panel's black top band left of the camera (where the message badges
    /// sit). The window is centred at `screen.midX + offset`, the notch at `screen.midX`.
    var leftBandWidth: CGFloat {
        max(0, panelSize.width / 2 - notchSize.width / 2 - CGFloat(settings.horizontalOffset))
    }

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

    init(nowPlaying: NowPlayingManager, settings: AppSettings, messageBadges: MessageBadgeMonitor) {
        self.nowPlaying = nowPlaying
        self.settings = settings
        self.messageBadges = messageBadges

        // Re-broadcast media and settings changes through this view model so a single
        // @ObservedObject in the view updates for state, media and settings changes.
        nowPlaying.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        messageBadges.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        // Fresh badge counts as soon as the panel starts opening.
        $isExpanded
            .removeDuplicates()
            .filter { $0 }
            .sink { [weak self] _ in self?.messageBadges.refreshNow() }
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
    ///
    /// Ignored while `expansionWillChange` runs: growing the window there triggers a nested
    /// positionWindow → refreshTracking → evaluateHover while `isExpanded` still has the OLD
    /// value. A delayed open clears `pendingOpen` before calling `setExpanded`, so without
    /// this guard that nested call would schedule a second, redundant pending open.
    func updateHover(isInside: Bool) {
        guard !isChangingExpansion else { return }
        // After a click-to-open collapse, don't reopen until the cursor has left the zone.
        if !isInside { suppressOpenUntilExit = false }
        if isInside, suppressOpenUntilExit { return }
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

    /// Set by `collapseNow()`; cleared by the next "outside" hover update.
    private var suppressOpenUntilExit = false

    /// Closes the panel immediately (after a badge / Now Playing click opened an app).
    func collapseNow() {
        pendingOpen?.cancel()
        pendingOpen = nil
        pendingClose?.cancel()
        pendingClose = nil
        suppressOpenUntilExit = true
        setExpanded(false)
    }

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
