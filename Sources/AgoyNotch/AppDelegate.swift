//
//  AppDelegate.swift
//  AgoyNotch
//
//  Wires the app together at launch: menu-bar-only (accessory) activation policy, the
//  AppSettings → Now Playing → view model → notch window chain, and the status item
//  (About / Settings… / Quit). "Opening the app" shows the Settings window: on launch
//  (unless turned off in Settings), whenever the user opens AgoyNotch again while it is
//  already running (reopen), from the status item, and via ⌘, in the app menu.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // Strong references so none of these are deallocated while the app runs.
    private var settings: AppSettings!
    private var nowPlaying: NowPlayingManager!
    private var viewModel: NotchViewModel!
    private var windowController: NotchWindowController!
    private var statusItem: NSStatusItem!

    /// Created on first use and reused afterwards.
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon by default — this is a menu-bar accessory. The Settings window
        // temporarily switches to `.regular` while it is open.
        NSApp.setActivationPolicy(.accessory)
        BundledAppIcon.apply()

        // Build the object graph.
        let settings = AppSettings()
        let nowPlaying = NowPlayingManager()
        let viewModel = NotchViewModel(nowPlaying: nowPlaying, settings: settings)
        let windowController = NotchWindowController(viewModel: viewModel, settings: settings)

        self.settings = settings
        self.nowPlaying = nowPlaying
        self.viewModel = viewModel
        self.windowController = windowController

        // Start the media service and show the notch overlay.
        nowPlaying.start()
        windowController.show()

        setupStatusItem()

        if settings.showSettingsOnLaunch {
            showSettings()
        }
    }

    /// Called when the user opens AgoyNotch (Finder, Spotlight, Launchpad, `open`) while it
    /// is already running: LaunchServices re-activates this instance instead of starting a
    /// second one, so show Settings here.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying?.stop()
    }

    // MARK: - Settings

    @objc func showSettings() {
        guard let settings else { return }
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                settings: settings,
                onActivationPolicyChange: { [weak self] in
                    self?.windowController?.ensureVisible()
                }
            )
        }
        settingsWindowController?.present()
    }

    // MARK: - Menu bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "AgoyNotch"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: "About AgoyNotch",
            action: #selector(showAbout),
            keyEquivalent: ""
        ).target = self

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        ).target = self

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit AgoyNotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.menu = menu
        self.statusItem = item
    }

    @objc private func showAbout() {
        // Bring the About panel to the front even though the app is an accessory.
        NSApp.activate()
        BundledAppIcon.apply()
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
