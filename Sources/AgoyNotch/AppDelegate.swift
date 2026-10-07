//
//  AppDelegate.swift
//  AgoyNotch
//
//  Wires the app together at launch: hides the Dock icon (accessory activation policy),
//  builds the Now Playing service → view model → window controller chain, shows the notch
//  panel, and installs the menu-bar status item with a Quit command. The collapsed↔expanded
//  morph is a SwiftUI spring inside a fixed-size window, so there is no resize to bridge.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Strong references so none of these are deallocated while the app runs.
    private var nowPlaying: NowPlayingManager!
    private var viewModel: NotchViewModel!
    private var windowController: NotchWindowController!
    private var statusItem: NSStatusItem!

    /// Manual notch adjustments, loaded from UserDefaults at launch. Each "Adjust Notch"
    /// menu action mutates this, persists it, and pushes it to the window controller.
    private var settings = NotchSettings()

    /// Step applied per nudge from the "Adjust Notch" menu, in points.
    private let adjustStep: CGFloat = 2

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, no app menu — this is a menu-bar accessory.
        NSApp.setActivationPolicy(.accessory)

        // Build the object graph.
        let nowPlaying = NowPlayingManager()
        let viewModel = NotchViewModel(nowPlaying: nowPlaying)
        let windowController = NotchWindowController(viewModel: viewModel)

        self.nowPlaying = nowPlaying
        self.viewModel = viewModel
        self.windowController = windowController

        // Start the media service and show the notch overlay.
        nowPlaying.start()
        windowController.show()

        // NOTE: the window no longer resizes on expand/collapse. It is permanently the
        // expanded size (see NotchViewModel.windowSize) so the hover tracking area always
        // covers the whole interactive panel — the fix for the "panel collapses when the
        // cursor reaches the transport buttons" bug. The collapsed↔expanded morph is a
        // SwiftUI spring drawn INSIDE the fixed window, so there is nothing to drive here.

        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying?.stop()
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

        // "Adjust Notch" submenu — fine-tunes the overlay so it lines up with the real
        // hardware notch. Each item nudges a persisted offset and repositions live.
        menu.addItem(.separator())
        let adjustItem = NSMenuItem(title: "Adjust Notch", action: nil, keyEquivalent: "")
        adjustItem.submenu = makeAdjustSubmenu()
        menu.addItem(adjustItem)

        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit AgoyNotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.menu = menu
        self.statusItem = item
    }

    /// Builds the "Adjust Notch" submenu. All items target `self`.
    private func makeAdjustSubmenu() -> NSMenu {
        let submenu = NSMenu()

        func add(_ title: String, _ selector: Selector) {
            submenu.addItem(withTitle: title, action: selector, keyEquivalent: "").target = self
        }

        add("Move Left", #selector(moveLeft))
        add("Move Right", #selector(moveRight))
        add("Move Down", #selector(moveDown))
        add("Move Up", #selector(moveUp))
        add("Wider", #selector(makeWider))
        add("Narrower", #selector(makeNarrower))
        add("Taller", #selector(makeTaller))
        add("Shorter", #selector(makeShorter))
        submenu.addItem(.separator())
        add("Reset Position", #selector(resetPosition))

        return submenu
    }

    // MARK: - Adjust Notch actions

    /// Persist the current `settings` and push them to the window controller so the overlay
    /// moves/resizes immediately. Shared by every adjustment action.
    private func commitSettings() {
        settings.save()
        windowController.applySettings(settings)
    }

    @objc private func moveLeft() {
        settings.horizontalOffset -= adjustStep
        commitSettings()
    }

    @objc private func moveRight() {
        settings.horizontalOffset += adjustStep
        commitSettings()
    }

    @objc private func moveDown() {
        settings.verticalOffset += adjustStep
        commitSettings()
    }

    @objc private func moveUp() {
        settings.verticalOffset -= adjustStep
        commitSettings()
    }

    @objc private func makeWider() {
        settings.widthAdjustment += adjustStep
        commitSettings()
    }

    @objc private func makeNarrower() {
        settings.widthAdjustment -= adjustStep
        commitSettings()
    }

    @objc private func makeTaller() {
        settings.heightAdjustment += adjustStep
        commitSettings()
    }

    @objc private func makeShorter() {
        settings.heightAdjustment -= adjustStep
        commitSettings()
    }

    @objc private func resetPosition() {
        settings.reset() // resets ALL offsets (horizontal, vertical, width, height) to 0.
        windowController.applySettings(settings)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
