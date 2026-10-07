//
//  SettingsView.swift
//  AgoyNotch
//
//  The Settings window's SwiftUI content: a grouped Form bound directly to AppSettings.
//  Every control writes straight into AppSettings, which persists it and applies it live
//  (no Save button, no restart).
//

import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {

    @ObservedObject var settings: AppSettings

    /// Launch-at-login state. The source of truth is SMAppService, not UserDefaults.
    @State private var loginEnabled = (SMAppService.mainApp.status == .enabled)
    @State private var loginError: String?

    /// SMAppService.mainApp only works for a real .app bundle (not `swift run` / Xcode's
    /// bare executable).
    private let isBundledApp = Bundle.main.bundleURL.pathExtension == "app"

    var body: some View {
        Form {
            hoverSection
            timingSection
            positionSection
            generalSection

            Section {
                HStack {
                    Spacer()
                    Button("Reset to defaults") { settings.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        // Flexible so the window can be resized and zoomed (green button).
        .frame(minWidth: 480, idealWidth: 480, minHeight: 480, idealHeight: 640)
        // The hosting view is reused across close/reopen, so re-read the real login-item
        // status every time the window appears.
        .onAppear { loginEnabled = (SMAppService.mainApp.status == .enabled) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            loginEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }

    // MARK: - Sections

    private var hoverSection: some View {
        Section {
            SliderRow(
                title: "Width",
                value: Binding(
                    get: { Double(settings.effectiveHoverSize.width) },
                    // Clamped (never 0), so dragging always leaves "match notch" mode and
                    // writes the stored hoverWidth that drives the tracking rect.
                    set: {
                        settings.hoverWidth = min(max($0.rounded(), AppSettings.Range.hoverWidth.lowerBound),
                                                  AppSettings.Range.hoverWidth.upperBound)
                    }
                ),
                range: AppSettings.Range.hoverWidth,
                step: 1,
                format: "%.0f pt"
            )
            SliderRow(
                title: "Height",
                value: Binding(
                    get: { Double(settings.effectiveHoverSize.height) },
                    set: {
                        settings.hoverHeight = min(max($0.rounded(), AppSettings.Range.hoverHeight.lowerBound),
                                                   AppSettings.Range.hoverHeight.upperBound)
                    }
                ),
                range: AppSettings.Range.hoverHeight,
                step: 1,
                format: "%.0f pt"
            )
            HStack {
                Text(String(format: "Detected notch: %.0f × %.0f pt",
                            Double(settings.measuredNotchSize.width),
                            Double(settings.measuredNotchSize.height)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Match notch") {
                    settings.hoverWidth = 0
                    settings.hoverHeight = 0
                }
            }
            SliderRow(
                title: "Vertical offset",
                value: $settings.hoverVerticalOffset,
                range: AppSettings.Range.hoverVerticalOffset,
                step: 1,
                format: "%.0f pt"
            )
        } header: {
            Text("Hover area")
        } footer: {
            Text("The invisible zone over your real notch that opens the panel. "
                 + "Vertical offset moves only this zone down; the panel always starts at the top of the screen.")
        }
    }

    private var timingSection: some View {
        Section {
            SliderRow(title: "Open delay", value: $settings.openDelay,
                      range: AppSettings.Range.delay, step: 0.05, format: "%.2f s")
            SliderRow(title: "Close delay", value: $settings.closeDelay,
                      range: AppSettings.Range.delay, step: 0.05, format: "%.2f s")
            SliderRow(title: "Animation duration", value: $settings.animationDuration,
                      range: AppSettings.Range.animationDuration, step: 0.05, format: "%.2f s")
        } header: {
            Text("Timing")
        } footer: {
            Text("Delays: 0 = instant. Moving away before the open delay ends cancels the open; "
                 + "coming back before the close delay ends keeps it open. Animation: 0 = no animation.")
        }
    }

    private var positionSection: some View {
        Section {
            SliderRow(title: "Horizontal offset", value: $settings.horizontalOffset,
                      range: AppSettings.Range.horizontalOffset, step: 1, format: "%+.0f pt")
            SliderRow(title: "Panel width", value: $settings.panelWidth,
                      range: AppSettings.Range.panelWidth, step: 1, format: "%.0f pt")
            SliderRow(title: "Panel height", value: $settings.panelHeight,
                      range: AppSettings.Range.panelHeight, step: 1, format: "%.0f pt")
        } header: {
            Text("Position & size")
        } footer: {
            Text("Horizontal offset shifts the panel and hover area left or right.")
        }
    }

    private var generalSection: some View {
        Section {
            Toggle("Show this window when AgoyNotch starts", isOn: $settings.showSettingsOnLaunch)

            Toggle("Launch at login", isOn: Binding(
                get: { loginEnabled },
                set: { setLaunchAtLogin($0) }
            ))
            .disabled(!isBundledApp)

            if !isBundledApp {
                Text("Launch at login only works from the built AgoyNotch.app (./scripts/build-app.sh).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let loginError {
                Text(loginError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("General")
        }
    }

    // MARK: - Launch at login

    /// Registers / unregisters the app as a login item. Errors are shown inline and the
    /// toggle re-syncs with the real status; nothing here can crash the app.
    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginEnabled = (SMAppService.mainApp.status == .enabled)
    }
}

// MARK: - Slider row

/// Title + live numeric readout on one line, slider underneath.
private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}
