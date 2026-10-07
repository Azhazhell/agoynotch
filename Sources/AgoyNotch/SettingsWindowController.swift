//
//  SettingsWindowController.swift
//  AgoyNotch
//
//  Owns the normal, titled Settings window (AppKit NSWindow hosting the SwiftUI
//  SettingsView). While it is open the app switches to the `.regular` activation policy so
//  it gets a Dock icon, an app menu and can come to the front; closing it switches back to
//  `.accessory` (menu-bar only).
//

import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    init(settings: AppSettings) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AgoyNotch Settings"
        // Reused across open/close; the controller keeps it alive.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        window.center()

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows the window in front of everything, with a Dock icon while it is open.
    func present() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
