//
//  BundledAppIcon.swift
//  AgoyNotch
//
//  Sets the Dock / About icon explicitly from the bundled AppIcon.icns. AgoyNotch is an
//  accessory (LSUIElement) app that switches to `.regular` while Settings is open, and the
//  Dock tile of a policy-switched app can otherwise come up as the generic app icon.
//

import AppKit

@MainActor
enum BundledAppIcon {

    /// `Contents/Resources/AppIcon.icns`; nil in the `swift run` dev flow (no bundle).
    static let image: NSImage? = Bundle.main.image(forResource: "AppIcon")

    /// Applies the bundled icon to the running app. Does nothing when there is no icon.
    static func apply() {
        guard let image else { return }
        NSApp.applicationIconImage = image
    }
}
