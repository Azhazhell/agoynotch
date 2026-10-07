//
//  NotchView.swift
//  AgoyNotch
//
//  The SwiftUI surface inside the notch window: ONE always-present black shape that grows
//  out of the hardware notch when the panel opens and shrinks back into it when it closes.
//
//  Why this fuses with the real notch: the shape is a full-width rectangle whose FLAT top
//  edge is at y = 0 of the window, which NotchWindowController pins to the physical top of
//  the screen (`screen.frame.maxY`). Its top band therefore covers the hardware notch AND
//  the menu-bar strip on both sides of it, so notch + panel read as one black shape whose
//  top edge is the top of the screen. Only the CONTENT is inset (notch height + 8 pt) so it
//  sits below the camera cutout; nothing outside the shape is padded or offset.
//
//  Morph: the shape's frame animates from the notch size to the panel size, anchored
//  top-center, using the spring from Settings → Animation duration (0 = instant). The
//  collapsed end state is fully invisible (opacity 0, no hit-testing), so when idle the
//  user sees only the real notch. The NSWindow is only the hover-zone size while collapsed;
//  the controller grows it to the panel size just before opening (before this morph starts)
//  and shrinks it after the close animation, so the morph always runs in the large window.
//

import SwiftUI

struct NotchView: View {

    /// Created in AppDelegate and injected, so this is `@ObservedObject`, not `@StateObject`.
    @ObservedObject var viewModel: NotchViewModel

    /// Convenience accessor for the current media snapshot.
    private var info: NowPlayingInfo { viewModel.nowPlaying.info }

    /// Bottom corner radius when expanded / collapsed. Top corners are always flat (0) so
    /// the top edge lies flush along the top of the screen.
    private let expandedBottomRadius: CGFloat = 22
    private let collapsedBottomRadius: CGFloat = 10

    var body: some View {
        let expanded = viewModel.isExpanded
        let panelSize = viewModel.panelSize
        let size = expanded ? panelSize : viewModel.notchSize
        let bottomRadius = expanded ? expandedBottomRadius : collapsedBottomRadius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )

        content
            // The ONLY top padding: inside the shape, so content clears the camera cutout.
            .padding(.top, viewModel.contentTopInset)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            // Laid out at the full panel size at all times so it never reflows mid-morph;
            // the clip below reveals it as the shape grows.
            .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
            .opacity(expanded ? 1 : 0)
            // The black shape: notch-sized when collapsed, panel-sized when expanded,
            // top-anchored so it grows down/out of the notch.
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(Color.black)
            .clipShape(shape)
            // Collapsed end state = fully invisible; hover is detected from the cursor
            // position in screen space (NotchWindowController), not by anything drawn here.
            .opacity(expanded ? 1 : 0)
            .allowsHitTesting(expanded)
            // Pin to the window's top-center: the shape's top edge is y = 0 = screen top.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Brief outline of the hover zone while its Settings are being adjusted.
            .overlay(alignment: .top) {
                hoverZonePreview
                    .animation(.easeOut(duration: 0.2), value: viewModel.showsHoverZonePreview)
            }
            // Full-bleed overlay: never let a reported safe area push the shape down.
            .ignoresSafeArea()
            .animation(viewModel.settings.animation, value: expanded)
    }

    // MARK: - Hover-zone preview

    /// The hover zone, outlined for a moment after a Hover-area / Horizontal-offset change.
    /// The window is centred on the zone's centre and top-anchored at the screen top, so
    /// this sits exactly on the screen-space hover zone. Purely visual: no hit-testing.
    @ViewBuilder
    private var hoverZonePreview: some View {
        if viewModel.showsHoverZonePreview {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                )
                .frame(width: viewModel.hoverSize.width, height: viewModel.hoverSize.height)
                .padding(.top, CGFloat(viewModel.settings.hoverVerticalOffset))
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: - Content

    /// The expanded panel body: the Now Playing section on the LEFT and the new live
    /// clock + calendar section on the RIGHT, separated by a subtle vertical divider —
    /// matching the NotchNook reference. Both columns sit below the camera cutout thanks to
    /// the top padding applied in `body`.
    private var content: some View {
        HStack(alignment: .top, spacing: 18) {
            // LEFT: the existing Now Playing section, unchanged.
            Group {
                if info.hasMedia {
                    nowPlayingPanel
                } else {
                    nothingPlayingPanel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Subtle vertical divider between the two sections.
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            // RIGHT: live clock (ticking seconds) + today's date / mini-week.
            ClockCalendarView(settings: viewModel.settings)
                .frame(width: 190, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The full Now Playing panel, laid out for the taller NotchNook-sized body: a top row
    /// with the (large) album art beside the title/album/artist stack and an Apple-Music
    /// glyph, and a row of transport controls beneath — all below the camera cutout.
    private var nowPlayingPanel: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Album art (placeholder when none) — enlarged for the NotchNook body.
                Group {
                    if let artwork = info.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.white.opacity(0.08)
                            Image(systemName: "music.note")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                // Title / album / artist stacked.
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.displayTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let album = info.album, !album.isEmpty {
                        Text(album)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if !info.displayArtist.isEmpty {
                        Text(info.displayArtist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Small Apple-Music-style glyph in the top-right.
                AppleMusicGlyph(size: 18)
            }

            // Transport controls, centered on their own row below the metadata.
            HStack(spacing: 34) {
                transportButton(system: "backward.fill", size: 20) { viewModel.nowPlaying.previous() }
                transportButton(system: info.isPlaying ? "pause.fill" : "play.fill",
                                size: 26) { viewModel.nowPlaying.togglePlayPause() }
                transportButton(system: "forward.fill", size: 20) { viewModel.nowPlaying.next() }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Tasteful placeholder shown in the expanded panel when nothing is playing.
    private var nothingPlayingPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundStyle(.white.opacity(0.6))
            Text("Nothing playing")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transportButton(system: String,
                                 size: CGFloat = 14,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Apple Music glyph

/// An Apple-Music-style activity glyph.
///
/// IMPORTANT: this is an SF Symbol STAND-IN (`music.note`) placed inside a small red/pink
/// rounded tile to EVOKE the Apple Music icon — it is deliberately NOT Apple's trademarked
/// Apple Music logo asset, which we must not ship.
private struct AppleMusicGlyph: View {
    var size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.25, blue: 0.42),
                             Color(red: 0.98, green: 0.12, blue: 0.30)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}
