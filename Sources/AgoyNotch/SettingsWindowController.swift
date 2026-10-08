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

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    /// Called after every activation-policy switch so the notch panel is re-shown (an
    /// activation-policy change can reorder or hide windows).
    private let onActivationPolicyChange: @MainActor () -> Void

    init(settings: AppSettings, onActivationPolicyChange: @escaping @MainActor () -> Void) {
        self.onActivationPolicyChange = onActivationPolicyChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            // .closable / .miniaturizable / .resizable enable the red / yellow / green buttons.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "AgoyNotch Settings"
        // Green zooms the window instead of making a full-screen Space.
        window.collectionBehavior = [.fullScreenNone]
        window.contentMinSize = NSSize(width: 480, height: 480)
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

    /// Shows the window in front of everything as the key window, with a Dock icon while it
    /// is open.
    func present() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            BundledAppIcon.apply()
            onActivationPolicyChange()
        }
        // Activate BEFORE ordering front so the window can become key (enabled traffic
        // lights, focusable controls).
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        // Activation right after a policy switch is sometimes ignored; retry once on the
        // next main-actor turn.
        Task { @MainActor [weak self] in
            BundledAppIcon.apply()
            NSApp.activate()
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        onActivationPolicyChange()
        // Re-show the notch panel again once AppKit has finished the policy switch.
        Task { @MainActor [weak self] in
            self?.onActivationPolicyChange()
        }
    }
}
