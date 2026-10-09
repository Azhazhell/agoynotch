//
//  AppLauncher.swift
//  AgoyNotch
//
//  Brings an app to the front by bundle ID (click a message badge or the Now Playing
//  block).
//
//  Why not just `NSRunningApplication.activate()`: since macOS 14 ("cooperative app
//  activation"), an app that is not itself active cannot pull another app forward with
//  activate(); the request is silently ignored. AgoyNotch is never active (its panel is
//  non-activating), so that call did nothing and the click only closed the panel.
//  Opening the app through Launch Services (NSWorkspace.openApplication) is a user-initiated
//  request that brings a running app forward too, so it is used for both cases.
//

import AppKit

@MainActor
enum AppLauncher {
    static func activate(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        _ = running?.unhide()

        // URL of the app: from the running instance if there is one, else from Launch Services.
        let url = running?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        guard let url else {
            // No bundle on disk (unusual): try a plain activate as a last resort.
            _ = running?.activate()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            #if DEBUG
            if let error { print("[AgoyNotch] open \(bundleID) failed: \(error)") }
            #endif
        }
    }
}
