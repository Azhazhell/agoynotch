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
    @ObservedObject var nowPlaying: NowPlayingManager
    @ObservedObject var messageBadges: MessageBadgeMonitor

    /// Launch-at-login state. The source of truth is SMAppService, not UserDefaults.
    @State private var loginEnabled = (SMAppService.mainApp.status == .enabled)
    @State private var loginError: String?

    /// SMAppService.mainApp only works for a real .app bundle (not `swift run` / Xcode's
    /// bare executable).
    private let isBundledApp = Bundle.main.bundleURL.pathExtension == "app"

    var body: some View {
        Form {
            hoverSection
            musicActivitySection
            messageBadgesSection
            timingSection
            appearanceSection
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
            Toggle("Show hover zone", isOn: $settings.showHoverZone)
        } header: {
            Text("Hover area")
        } footer: {
            Text("The invisible zone over your real notch that opens the panel. "
                 + "It always includes the very top edge of the screen and reaches down by Height. "
                 + "Turn on Show hover zone to keep it outlined; it also flashes while you drag. "
                 + "Parts hidden behind the physical notch can't be drawn. "
                 + "A zone wider than the notch also opens the panel from menu-bar items beside it.")
        }
    }

    private var musicActivitySection: some View {
        Section {
            Toggle("Show music activity beside the notch", isOn: $settings.showMusicActivity)
            ColorPicker("Equalizer colour", selection: $settings.equalizerColor, supportsOpacity: true)
            Text(nowPlaying.adapterStatus.settingsText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Music activity")
        } footer: {
            Text("While something is playing (Apple Music, Spotify, Apple TV, or YouTube / "
                 + "SoundCloud / Spotify in a browser) and the panel is closed, a small black pill beside the notch "
                 + "shows the artwork and a moving equalizer. Hovering it opens the panel. "
                 + "Paused or nothing playing = nothing is shown.")
        }
    }

    private var messageBadgesSection: some View {
        Section {
            Toggle("Show message badges in the open panel", isOn: $settings.showMessageBadges)
            Toggle(MessageApp.messages.settingsTitle, isOn: $settings.badgeMessages)
                .disabled(!settings.showMessageBadges)
            Toggle(MessageApp.whatsapp.settingsTitle, isOn: $settings.badgeWhatsApp)
                .disabled(!settings.showMessageBadges)
            Toggle("Red dot beside the notch while closed", isOn: $settings.showCollapsedBadgeDot)
                .disabled(!settings.showMessageBadges)
            if settings.showMessageBadges {
                if messageBadges.isTrusted {
                    Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Label("Accessibility access needed", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Grant access…") { messageBadges.requestAccess() }
                    }
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("While the panel is open, shows the Messages and WhatsApp icons with the unread count from "
                 + "their Dock badge. The apps must be running (in the background is fine). "
                 + "Only the number is read, never your messages. Needs Accessibility access; "
                 + "macOS asks again after every reinstall. The count only shows when System Settings → "
                 + "Notifications → Messages / WhatsApp → Badge application icon is on. "
                 + "The red dot needs room beside the notch (Show music activity on, or a hover zone wider "
                 + "than the notch). If you just allowed access and nothing appears, quit and reopen AgoyNotch.")
        }
    }

    private var appearanceSection: some View {
        Section {
            ClockColorPreview(settings: settings)
            ColorPicker("Clock (hours:minutes)", selection: $settings.clockColor, supportsOpacity: true)
            ColorPicker("Seconds", selection: $settings.secondsColor, supportsOpacity: true)
            ColorPicker("Date & month", selection: $settings.dateColor, supportsOpacity: true)
            ColorPicker("Weekday letters", selection: $settings.weekdayColor, supportsOpacity: true)
            ColorPicker("Today highlight", selection: $settings.todayHighlightColor, supportsOpacity: true)
            ColorPicker("Today number", selection: $settings.todayTextColor, supportsOpacity: true)
            HStack {
                Spacer()
                Button("Reset colours") { settings.resetAppearance() }
            }
        } header: {
            Text("Clock & Calendar")
        } footer: {
            Text("Colours apply live to the expanded panel.")
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

// MARK: - Now Playing source

private extension AdapterStatus {
    var settingsText: String {
        switch self {
        case .running:
            return "Now Playing source: all apps (Music, Spotify, TV, browsers)"
        case .starting:
            return "Now Playing source: starting…"
        case .notBundled:
            return "Now Playing source: Apple Music only (helper not bundled — use the app built by build-app.sh)"
        case .failed(let reason):
            return "Now Playing source: Apple Music only — \(reason)"
        }
    }
}

// MARK: - Clock colour preview

/// A small live sample of the clock + calendar colours on the panel's black background, so
/// colour changes are visible without hovering the notch.
private struct ClockColorPreview: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            HStack(spacing: 0) {
                Text("12:34").foregroundStyle(settings.clockColor)
                Text(":56").foregroundStyle(settings.secondsColor)
            }
            .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Aug")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(settings.dateColor.opacity(0.7))
                Text("7")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(settings.dateColor)
            }

            VStack(spacing: 3) {
                Text("M T W")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(settings.weekdayColor)
                HStack(spacing: 4) {
                    Text("6")
                        .foregroundStyle(settings.dateColor.opacity(0.85))
                    Text("7")
                        .fontWeight(.bold)
                        .foregroundStyle(settings.todayTextColor)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(settings.todayHighlightColor))
                    Text("8")
                        .foregroundStyle(settings.dateColor.opacity(0.85))
                }
                .font(.system(size: 11))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black))
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
