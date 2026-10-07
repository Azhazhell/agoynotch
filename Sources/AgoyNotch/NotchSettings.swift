//
//  NotchSettings.swift
//  AgoyNotch
//
//  User-adjustable fine-tuning for the notch overlay, persisted in UserDefaults.
//
//  The window controller auto-detects the hardware notch geometry (see
//  NotchWindowController). That measurement is correct on most Macs, but the exact pixel
//  seam between the physical notch and the overlay can differ slightly across models.
//  These four offsets let the user nudge the overlay so it lines up perfectly with their
//  own hardware notch. They are ADDED ON TOP of the auto-detected geometry — the app still
//  measures the notch first, then applies these adjustments.
//
//  Everything here is local-only: values live in the standard UserDefaults suite on the
//  user's Mac. No network, no telemetry.
//

import CoreGraphics
import Foundation

/// Persisted manual adjustments layered on top of the auto-detected notch geometry.
///
/// All values are in points and default to `0`, i.e. "use the auto-detected geometry
/// unchanged". They are stored in `UserDefaults.standard` so they survive relaunches.
struct NotchSettings {

    /// UserDefaults keys. Namespaced to avoid colliding with any other defaults.
    private enum Key {
        static let horizontalOffset = "AgoyNotch.horizontalOffset"
        static let verticalOffset   = "AgoyNotch.verticalOffset"
        static let widthAdjustment  = "AgoyNotch.widthAdjustment"
        static let heightAdjustment = "AgoyNotch.heightAdjustment"
    }

    /// Shifts the overlay left (negative) / right (positive) from the auto-detected center.
    var horizontalOffset: CGFloat

    /// Nudges the overlay down from the top edge of the screen (positive = further down).
    var verticalOffset: CGFloat

    /// Added to the measured collapsed pill width (positive = wider, negative = narrower).
    var widthAdjustment: CGFloat

    /// Added to the measured collapsed pill HEIGHT, i.e. how far down the collapsed black
    /// shape extends from the top of the screen (positive = taller / more vertical
    /// coverage, negative = shorter). Lets the user make the overlay exactly cover their
    /// real notch's height when `safeAreaInsets.top` is a hair off.
    var heightAdjustment: CGFloat

    // MARK: - Persistence

    /// The UserDefaults suite to read from / write to. Defaults to `.standard`.
    private let defaults: UserDefaults

    /// Load the current settings from the given defaults suite (standard by default).
    /// Missing keys read back as `0` — `UserDefaults.double(forKey:)` returns `0` when a
    /// key is absent, which matches the documented default for every offset.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.horizontalOffset = CGFloat(defaults.double(forKey: Key.horizontalOffset))
        self.verticalOffset   = CGFloat(defaults.double(forKey: Key.verticalOffset))
        self.widthAdjustment  = CGFloat(defaults.double(forKey: Key.widthAdjustment))
        self.heightAdjustment = CGFloat(defaults.double(forKey: Key.heightAdjustment))
    }

    /// Persist the current values back to the defaults suite.
    func save() {
        defaults.set(Double(horizontalOffset), forKey: Key.horizontalOffset)
        defaults.set(Double(verticalOffset), forKey: Key.verticalOffset)
        defaults.set(Double(widthAdjustment), forKey: Key.widthAdjustment)
        defaults.set(Double(heightAdjustment), forKey: Key.heightAdjustment)
    }

    /// Reset all adjustments back to `0` (pure auto-detected geometry) and persist.
    mutating func reset() {
        horizontalOffset = 0
        verticalOffset = 0
        widthAdjustment = 0
        heightAdjustment = 0
        save()
    }
}
