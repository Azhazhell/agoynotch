//
//  AppLauncher.swift
//  AgoyNotch
//
//  Brings an app to the front by bundle ID (click a message badge or the Now Playing
//  block): activates it if running, otherwise launches it.
//

import AppKit

@MainActor
enum AppLauncher {
    static func activate(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            _ = app.unhide()
            _ = app.activate()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            #if DEBUG
            if let error { print("[AgoyNotch] open \(bundleID) failed: \(error)") }
            #endif
        }
    }
}
