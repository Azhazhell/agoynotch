//
//  MessageBadgeMonitor.swift
//  AgoyNotch
//
//  Publishes the Messages / WhatsApp unread badges for the open panel. Every 3 s (and once
//  more when the panel opens) it reads the Dock's badge text via DockBadgeReader on a private
//  background queue, then publishes the result on the main actor.
//
//  While Settings → Show message badges is OFF (the default) nothing is read from the Dock
//  and no Accessibility prompt is shown. At most one automatic prompt per launch; the
//  Settings "Grant access…" button can always prompt again.
//

import AppKit
import ApplicationServices
import Combine

@MainActor
final class MessageBadgeMonitor: ObservableObject {

    /// Badges to show, in `MessageApp.allCases` order. Non-empty ⇒ master on ∧ app on ∧ trusted.
    @Published private(set) var badges: [MessageBadge] = []
    /// Whether AgoyNotch has Accessibility access (drives the Settings status line).
    @Published private(set) var isTrusted = AXIsProcessTrusted()

    private let settings: AppSettings
    private let queue = DispatchQueue(label: "com.agoynotch.dockbadges", qos: .utility)
    private var poll: Task<Void, Never>?
    private var readInFlight = false
    private var didPromptThisLaunch = false
    private var loggedFailures: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        guard poll == nil else { return }

        // Replays the current values at subscribe time: that is how an enabled feature
        // prompts (once) and reads at launch. `.receive(on:)` so the sink sees the new values
        // (@Published emits on willSet).
        settings.$showMessageBadges
            .merge(with: settings.$badgeMessages, settings.$badgeWhatsApp)
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.promptIfNeeded()
                self?.tick()
            }
            .store(in: &cancellables)

        poll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    func stop() {
        poll?.cancel()
        poll = nil
        cancellables.removeAll()
    }

    /// Settings "Grant access…": always shows the system prompt, then opens the
    /// Accessibility pane of System Settings.
    func requestAccess() {
        didPromptThisLaunch = true
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        tick()
    }

    /// Called by NotchViewModel when the panel starts expanding.
    func refreshNow() {
        tick()
    }

    // MARK: - Private

    private func promptIfNeeded() {
        guard settings.showMessageBadges, !AXIsProcessTrusted(), !didPromptThisLaunch else { return }
        didPromptThisLaunch = true
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    private var enabledApps: [MessageApp] {
        MessageApp.allCases.filter(settings.isBadgeEnabled)
    }

    private func clearBadges() {
        if !badges.isEmpty { badges = [] }
    }

    private func tick() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }

        let enabled = enabledApps
        // Off or untrusted: no Dock IPC at all (FR-10).
        guard !enabled.isEmpty, trusted else {
            clearBadges()
            return
        }
        guard !readInFlight else { return }

        var targets: [DockBadgeTarget] = []
        for app in enabled {
            for bundleID in app.bundleIDs {
                if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                    targets.append(DockBadgeTarget(app: app, bundleID: bundleID,
                                                   localizedName: running.localizedName))
                }
            }
        }
        // No chat app running → no badge possible.
        guard !targets.isEmpty else {
            clearBadges()
            return
        }
        guard let dockPID = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier else {
            logOnce("Dock not running")
            clearBadges()
            return
        }

        readInFlight = true
        queue.async { [weak self] in
            let result = DockBadgeReader.read(dockPID: dockPID, targets: targets)
            Task { @MainActor in self?.finishRead(result) }
        }
    }

    private func finishRead(_ result: DockBadgeReadResult) {
        readInFlight = false

        // Settings or trust may have changed while the read was in flight.
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        let enabled = enabledApps
        guard trusted, !enabled.isEmpty else {
            clearBadges()
            return
        }

        switch result {
        case .ok(let list):
            let shown = list.filter { enabled.contains($0.app) }
            if shown != badges { badges = shown }
        case .failed(let message):
            clearBadges()
            logOnce(message)
        }
    }

    /// Logs each distinct failure once per launch.
    private func logOnce(_ message: String) {
        guard !loggedFailures.contains(message) else { return }
        loggedFailures.insert(message)
        AgoyLog.write("message badges: " + message)
    }
}
