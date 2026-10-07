//
//  AppSettings.swift
//  AgoyNotch
//
//  The single source of truth for every user setting (hover zone size, open/close delays,
//  animation speed, position/size fine-tuning, Clock & Calendar colours, launch
//  behaviour). Colours are stored as sRGB "RRGGBBAA" hex strings. Each value is a
//  `@Published` property persisted to UserDefaults in its `didSet`, so the Settings window
//  binds to it directly and every change is applied LIVE: NotchViewModel forwards
//  `objectWillChange` (the view redraws), NotchWindowController subscribes to the geometry
//  properties (window repositioned + tracking rebuilt), and delays / animation are read at
//  the moment they are used.
//
//  Everything is local-only (standard UserDefaults suite). No network, no telemetry.
//

import AppKit
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
        // Clock & Calendar colours, stored as sRGB "RRGGBBAA" hex strings.
        static let clockColor = "AgoyNotch.v2.clockColor"
        static let secondsColor = "AgoyNotch.v2.secondsColor"
        static let dateColor = "AgoyNotch.v2.dateColor"
        static let weekdayColor = "AgoyNotch.v2.weekdayColor"
        static let todayHighlightColor = "AgoyNotch.v2.todayHighlightColor"
        static let todayTextColor = "AgoyNotch.v2.todayTextColor"

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
        // Kept to ±60 pt: the hover zone (~186 pt wide, half ≈ 93) must still overlap the
        // hardware notch, and the narrowest panel (480 pt, half 240) must still cover it.
        // At ±150 the hover zone slid off the notch and a sliver of the real notch showed.
        static let horizontalOffset: ClosedRange<Double> = -60...60
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
        // Colours matching the original look (explicit sRGB so they round-trip exactly).
        static let clockColor = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        static let secondsColor = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        /// Month label is drawn at ×0.7 and week numbers at ×0.85 of this, as before.
        static let dateColor = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        static let weekdayColor = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 0.5)
        static let todayHighlightColor = Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1)
        static let todayTextColor = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
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

    // MARK: - Clock & Calendar colours (persisted as sRGB hex)

    /// Clock hours:minutes ("HH:mm").
    @Published var clockColor: Color = Default.clockColor {
        didSet { storeColor(clockColor, Key.clockColor) }
    }
    /// Clock seconds (":ss").
    @Published var secondsColor: Color = Default.secondsColor {
        didSet { storeColor(secondsColor, Key.secondsColor) }
    }
    /// Month label, big day number and week-strip numbers.
    @Published var dateColor: Color = Default.dateColor {
        didSet { storeColor(dateColor, Key.dateColor) }
    }
    /// Weekday letters in the week strip.
    @Published var weekdayColor: Color = Default.weekdayColor {
        didSet { storeColor(weekdayColor, Key.weekdayColor) }
    }
    /// The circle behind today's number in the week strip.
    @Published var todayHighlightColor: Color = Default.todayHighlightColor {
        didSet { storeColor(todayHighlightColor, Key.todayHighlightColor) }
    }
    /// Today's number, drawn on top of the highlight circle.
    @Published var todayTextColor: Color = Default.todayTextColor {
        didSet { storeColor(todayTextColor, Key.todayTextColor) }
    }

    private func storeColor(_ color: Color, _ key: String) {
        if let hex = Self.hexRGBA(from: color) {
            defaults.set(hex, forKey: key)
        }
    }

    /// `Color` → "RRGGBBAA" in sRGB, or nil if the colour can't be converted.
    static func hexRGBA(from color: Color) -> String? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        func byte(_ v: CGFloat) -> Int { Int(min(max((v * 255).rounded(), 0), 255)) }
        return String(format: "%02X%02X%02X%02X",
                      byte(c.redComponent), byte(c.greenComponent),
                      byte(c.blueComponent), byte(c.alphaComponent))
    }

    /// "RRGGBBAA" (sRGB) → `Color`, or nil if the string is malformed.
    static func color(fromHex hex: String) -> Color? {
        guard hex.count == 8, let v = UInt32(hex, radix: 16) else { return nil }
        func component(_ shift: UInt32) -> Double { Double((v >> shift) & 0xFF) / 255 }
        return Color(.sRGB, red: component(24), green: component(16),
                     blue: component(8), opacity: component(0))
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

        func loadColor(_ key: String, _ fallback: Color) -> Color {
            defaults.string(forKey: key).flatMap { Self.color(fromHex: $0) } ?? fallback
        }
        clockColor = loadColor(Key.clockColor, Default.clockColor)
        secondsColor = loadColor(Key.secondsColor, Default.secondsColor)
        dateColor = loadColor(Key.dateColor, Default.dateColor)
        weekdayColor = loadColor(Key.weekdayColor, Default.weekdayColor)
        todayHighlightColor = loadColor(Key.todayHighlightColor, Default.todayHighlightColor)
        todayTextColor = loadColor(Key.todayTextColor, Default.todayTextColor)

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
        resetAppearance()
    }

    /// Restores the Clock & Calendar colours only.
    func resetAppearance() {
        clockColor = Default.clockColor
        secondsColor = Default.secondsColor
        dateColor = Default.dateColor
        weekdayColor = Default.weekdayColor
        todayHighlightColor = Default.todayHighlightColor
        todayTextColor = Default.todayTextColor
    }
}
