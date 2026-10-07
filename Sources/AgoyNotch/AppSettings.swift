//
//  AppSettings.swift
//  AgoyNotch
//
//  The single source of truth for every user setting (hover zone size, open/close delays,
//  animation speed, position/size fine-tuning, launch behaviour). Each value is a
//  `@Published` property persisted to UserDefaults in its `didSet`, so the Settings window
//  binds to it directly and every change is applied LIVE: NotchViewModel forwards
//  `objectWillChange` (the view redraws), NotchWindowController subscribes to the geometry
//  properties (window repositioned + tracking rebuilt), and delays / animation are read at
//  the moment they are used.
//
//  Everything is local-only (standard UserDefaults suite). No network, no telemetry.
//

import Foundation
import SwiftUI

@MainActor
final class AppSettings: ObservableObject {

    // MARK: - Keys / ranges / defaults

    /// UserDefaults keys. `v2` prefix: the v1 keys belonged to the old menu-based "nudge"
    /// geometry and are deliberately dropped (see `init`).
    enum Key {
        static let hoverWidth = "AgoyNotch.v2.hoverWidth"
        static let hoverHeight = "AgoyNotch.v2.hoverHeight"
        static let hoverVerticalOffset = "AgoyNotch.v2.hoverVerticalOffset"
        static let horizontalOffset = "AgoyNotch.v2.horizontalOffset"
        static let panelWidth = "AgoyNotch.v2.panelWidth"
        static let panelHeight = "AgoyNotch.v2.panelHeight"
        static let openDelay = "AgoyNotch.v2.openDelay"
        static let closeDelay = "AgoyNotch.v2.closeDelay"
        static let animationDuration = "AgoyNotch.v2.animationDuration"
        static let showSettingsOnLaunch = "AgoyNotch.v2.showSettingsOnLaunch"

        /// Keys from the removed `NotchSettings` struct, cleared once on launch.
        static let legacy = [
            "AgoyNotch.horizontalOffset",
            "AgoyNotch.verticalOffset",
            "AgoyNotch.widthAdjustment",
            "AgoyNotch.heightAdjustment",
        ]
    }

    /// Allowed slider ranges (points or seconds).
    enum Range {
        static let hoverWidth: ClosedRange<Double> = 80...400
        static let hoverHeight: ClosedRange<Double> = 10...80
        static let hoverVerticalOffset: ClosedRange<Double> = 0...40
        static let horizontalOffset: ClosedRange<Double> = -150...150
        static let panelWidth: ClosedRange<Double> = 480...800
        static let panelHeight: ClosedRange<Double> = 180...320
        static let delay: ClosedRange<Double> = 0...2
        static let animationDuration: ClosedRange<Double> = 0...1
    }

    /// Factory defaults, also used by "Reset to defaults".
    enum Default {
        /// 0 = "match my measured notch" for the hover width/height.
        static let hoverWidth: Double = 0
        static let hoverHeight: Double = 0
        static let hoverVerticalOffset: Double = 0
        static let horizontalOffset: Double = 0
        static let panelWidth: Double = 600
        static let panelHeight: Double = 240
        static let openDelay: Double = 0.0
        static let closeDelay: Double = 0.35
        static let animationDuration: Double = 0.35
        static let showSettingsOnLaunch = true
    }

    private let defaults: UserDefaults

    // MARK: - Persisted settings

    /// Width of the collapsed hover zone over the notch. 0 = use the measured notch width.
    @Published var hoverWidth: Double = Default.hoverWidth { didSet { defaults.set(hoverWidth, forKey: Key.hoverWidth) } }
    /// Height of the collapsed hover zone. 0 = use the measured notch height.
    @Published var hoverHeight: Double = Default.hoverHeight { didSet { defaults.set(hoverHeight, forKey: Key.hoverHeight) } }
    /// Moves ONLY the hover zone down from the top of the screen. The panel itself always
    /// starts at the very top of the screen (moving it down would re-create the gap under
    /// the notch).
    @Published var hoverVerticalOffset: Double = Default.hoverVerticalOffset {
        didSet { defaults.set(hoverVerticalOffset, forKey: Key.hoverVerticalOffset) }
    }
    /// Shifts the whole overlay (panel + hover zone) left (−) / right (+).
    @Published var horizontalOffset: Double = Default.horizontalOffset {
        didSet { defaults.set(horizontalOffset, forKey: Key.horizontalOffset) }
    }
    /// Expanded panel width.
    @Published var panelWidth: Double = Default.panelWidth { didSet { defaults.set(panelWidth, forKey: Key.panelWidth) } }
    /// Expanded panel height (measured from the very top of the screen, notch included).
    @Published var panelHeight: Double = Default.panelHeight { didSet { defaults.set(panelHeight, forKey: Key.panelHeight) } }
    /// Seconds the cursor must stay over the notch before the panel opens. 0 = instant.
    @Published var openDelay: Double = Default.openDelay { didSet { defaults.set(openDelay, forKey: Key.openDelay) } }
    /// Seconds after the cursor leaves the panel before it closes. 0 = instant.
    @Published var closeDelay: Double = Default.closeDelay { didSet { defaults.set(closeDelay, forKey: Key.closeDelay) } }
    /// Spring response of the open/close animation. 0 = no animation.
    @Published var animationDuration: Double = Default.animationDuration {
        didSet { defaults.set(animationDuration, forKey: Key.animationDuration) }
    }
    /// Show the Settings window every time the app starts.
    @Published var showSettingsOnLaunch: Bool = Default.showSettingsOnLaunch {
        didSet { defaults.set(showSettingsOnLaunch, forKey: Key.showSettingsOnLaunch) }
    }

    // MARK: - Runtime (not persisted)

    /// The hardware notch size of the current screen. Set by NotchWindowController whenever
    /// it positions the window; used as the default hover size and for the content inset.
    @Published var measuredNotchSize = CGSize(width: 200, height: 32)

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        func load(_ key: String, _ fallback: Double, _ range: ClosedRange<Double>,
                  zeroMeansAuto: Bool = false) -> Double {
            let value = defaults.object(forKey: key) as? Double ?? fallback
            if zeroMeansAuto && value == 0 { return 0 }
            return min(max(value, range.lowerBound), range.upperBound)
        }

        // Assignments inside init do not trigger didSet, so loading never re-writes defaults.
        hoverWidth = load(Key.hoverWidth, Default.hoverWidth, Range.hoverWidth, zeroMeansAuto: true)
        hoverHeight = load(Key.hoverHeight, Default.hoverHeight, Range.hoverHeight, zeroMeansAuto: true)
        hoverVerticalOffset = load(Key.hoverVerticalOffset, Default.hoverVerticalOffset,
                                   Range.hoverVerticalOffset)
        horizontalOffset = load(Key.horizontalOffset, Default.horizontalOffset, Range.horizontalOffset)
        panelWidth = load(Key.panelWidth, Default.panelWidth, Range.panelWidth)
        panelHeight = load(Key.panelHeight, Default.panelHeight, Range.panelHeight)
        openDelay = load(Key.openDelay, Default.openDelay, Range.delay)
        closeDelay = load(Key.closeDelay, Default.closeDelay, Range.delay)
        animationDuration = load(Key.animationDuration, Default.animationDuration,
                                 Range.animationDuration)
        showSettingsOnLaunch = defaults.object(forKey: Key.showSettingsOnLaunch) as? Bool
            ?? Default.showSettingsOnLaunch

        for key in Key.legacy {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Derived values

    /// The collapsed hover zone actually used: 0 resolves to the measured notch, and the
    /// result is clamped to the slider ranges.
    var effectiveHoverSize: CGSize {
        let w = hoverWidth > 0 ? hoverWidth : Double(measuredNotchSize.width)
        let h = hoverHeight > 0 ? hoverHeight : Double(measuredNotchSize.height)
        return CGSize(
            width: min(max(w, Range.hoverWidth.lowerBound), Range.hoverWidth.upperBound),
            height: min(max(h, Range.hoverHeight.lowerBound), Range.hoverHeight.upperBound)
        )
    }

    /// The open/close animation, or `nil` (instant) when the duration is 0.
    var animation: Animation? {
        animationDuration <= 0 ? nil : .spring(response: animationDuration, dampingFraction: 0.82)
    }

    /// Restores every persisted setting to its factory default (persisted via didSet).
    func resetToDefaults() {
        hoverWidth = Default.hoverWidth
        hoverHeight = Default.hoverHeight
        hoverVerticalOffset = Default.hoverVerticalOffset
        horizontalOffset = Default.horizontalOffset
        panelWidth = Default.panelWidth
        panelHeight = Default.panelHeight
        openDelay = Default.openDelay
        closeDelay = Default.closeDelay
        animationDuration = Default.animationDuration
        showSettingsOnLaunch = Default.showSettingsOnLaunch
    }
}
