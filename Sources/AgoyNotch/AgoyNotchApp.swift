//
//  AgoyNotchApp.swift
//  AgoyNotch
//
//  @main entry point. AgoyNotch's windows (the notch panel and the Settings window) are
//  AppKit-managed and created in AppDelegate, so there is no SwiftUI WindowGroup. An `App`
//  needs at least one scene, so we keep an empty `Settings` scene (it opens no window on
//  launch) and redirect its app-menu "Settings…" command (visible while the Settings
//  window puts the app in `.regular` mode) to our own AppKit Settings window.
//

import SwiftUI

@main
struct AgoyNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            // Replace SwiftUI's built-in "Settings…" (which would open the empty scene above)
            // so ⌘, opens the real Settings window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
