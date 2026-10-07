//
//  MacNotchApp.swift
//  MacNotch
//
//  @main entry point. Because MacNotch is a menu-bar accessory whose only window is an
//  AppKit-managed NSPanel (created in AppDelegate), there is no SwiftUI WindowGroup. We use
//  `@NSApplicationDelegateAdaptor` to hand lifecycle to AppDelegate and a `Settings` scene
//  with an EmptyView as the body — a Settings scene creates NO visible window on launch for
//  an `.accessory` app, so nothing extra appears on screen; the notch panel is the only UI.
//

import SwiftUI

@main
struct MacNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window — the notch panel is created and managed by AppDelegate.
        Settings {
            EmptyView()
        }
    }
}
