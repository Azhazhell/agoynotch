//
//  AppDelegate.swift
//  MacNotch
//
//  Wires the app together at launch: hides the Dock icon (accessory activation policy),
//  builds the Now Playing service → view model → window controller chain, shows the notch
//  panel, and installs the menu-bar status item with a Quit command. Also bridges the view
//  model's expand/collapse state to the window controller so the panel resizes.
//

import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    // Strong references so none of these are deallocated while the app runs.
    private var nowPlaying: NowPlayingManager!
    private var viewModel: NotchViewModel!
    private var windowController: NotchWindowController!
    private var statusItem: NSStatusItem!

    private var cancellables = Set<AnyCancellable>()

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

        // When the panel expands/collapses, resize & recenter the window with animation.
        viewModel.$isExpanded
            .removeDuplicates()
            .sink { [weak windowController] _ in
                windowController?.layoutForStateChange()
            }
            .store(in: &cancellables)

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
            accessibilityDescription: "MacNotch"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: "About MacNotch",
            action: #selector(showAbout),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit MacNotch",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        item.menu = menu
        self.statusItem = item
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
