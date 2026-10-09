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
//  collapsed end state is fully invisible (opacity 0, no hit-testing) unless any Now Playing
//  app is playing: then it is the music activity pill, a black shape exactly the notch's height
//  fused with the notch, with artwork on the left wing and an equalizer on the right (see
//  MusicActivityView.swift). The morph grows from the pill when it is showing, else from
//  the bare notch. The NSWindow is only the hover-zone (or pill) size while collapsed;
//  the controller grows it to the panel size just before opening (before this morph starts)
//  and shrinks it after the close animation, so the morph always runs in the large window.
//

import SwiftUI

/// The EXPANDED panel outline, NotchNook style. The body is a black rounded rectangle
/// hanging from the top of the screen, inset by `flareRadius` on each side. At the two TOP
/// OUTER corners the side edges flare OUTWARD as they rise, reaching the full width at the
/// very top of the screen (y = 0): the panel gets wider toward the top, like the opening of
/// a "V", and blends into the menu-bar edge. Material is ADDED at the top corners, never cut
/// away. The bottom corners are ordinary convex rounded corners.
///
/// Each flare is a quadratic curve from the body edge at y = r up to the full width at
/// y = 0, with its control point at (body edge x, 0). Midpoint check on the right flare
/// (w = 600, r = 12): from (588, 12) to (600, 0), control (588, 0) -> midpoint (591, 3).
/// The straight line between the end points passes x = 597 at y = 3, so the curve hugs the
/// top edge and sweeps out smoothly: an inverted (concave) fillet, like the Dynamic Island.
struct NotchPanelShape: Shape {
    /// How far each top corner flares out beyond the body, in points.
    var flareRadius: CGFloat
    /// Convex bottom corner radius.
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        guard w > 0, h > 0 else { return Path() }

        // Flare: at most a quarter of the width and half the height.
        let r = max(0, min(flareRadius, w / 4, h / 2))
        let left = rect.minX + r          // body left edge
        let right = rect.maxX - r         // body right edge
        // Bottom corners fit inside the body width and below the flare.
        let b = max(0, min(bottomRadius, (right - left) / 2, h - r))

        var p = Path()
        // Full-width top edge at the very top of the screen.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Right flare: from the top-right down and inward to the body edge.
        p.addQuadCurve(to: CGPoint(x: right, y: rect.minY + r),
                       control: CGPoint(x: right, y: rect.minY))
        // Right side, convex bottom-right corner, bottom edge, convex bottom-left corner.
        p.addLine(to: CGPoint(x: right, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: right - b, y: rect.maxY),
                       control: CGPoint(x: right, y: rect.maxY))
        p.addLine(to: CGPoint(x: left + b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: left, y: rect.maxY - b),
                       control: CGPoint(x: left, y: rect.maxY))
        // Left side up to the flare, then out to the top-left corner.
        p.addLine(to: CGPoint(x: left, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY),
                       control: CGPoint(x: left, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Responsive sizes for the EXPANDED panel content, all derived from the panel height so the
/// one short row of content (artwork + metadata + transport, and the clock/calendar column)
/// scales down and tightens as the panel is made thinner — never clipped, even at the 90 pt
/// minimum. `availableHeight` is the usable area inside the black shape: the panel height
/// minus the content top inset (which clears the camera cutout) minus the bottom padding.
struct PanelMetrics {
    let panelSize: CGSize
    let contentTopInset: CGFloat

    /// Bottom padding inside the shape; shrinks with the panel so the row stays centred.
    var bottomPadding: CGFloat { clamp(availableRaw * 0.12, 6, 18) }
    var horizontalPadding: CGFloat { clamp(panelSize.width * 0.03, 12, 20) }

    /// Height actually available for the content row (never negative).
    private var availableRaw: CGFloat { panelSize.height - contentTopInset }
    var availableHeight: CGFloat { max(availableRaw - bottomPadding, 0) }

    // MARK: - Now Playing

    /// Album art side: fills most of the available row height. Clamped to a tasteful band,
    /// but never taller than the available height itself, so it can't be clipped even if the
    /// measured notch is tall and the panel is at its 90 pt minimum.
    var artSide: CGFloat { min(clamp(availableHeight * 0.9, 36, 72), max(availableHeight, 24)) }
    var artCornerRadius: CGFloat { clamp(artSide * 0.18, 6, 14) }
    var artSpacing: CGFloat { clamp(artSide * 0.18, 8, 16) }
    var columnSpacing: CGFloat { clamp(panelSize.width * 0.025, 10, 18) }

    var titleFont: CGFloat { clamp(artSide * 0.22, 12, 16) }
    var subtitleFont: CGFloat { clamp(artSide * 0.17, 10, 13) }
    var titleSpacing: CGFloat { clamp(artSide * 0.05, 2, 4) }

    var transportSide: CGFloat { clamp(artSide * 0.26, 14, 20) }
    var transportSpacing: CGFloat { clamp(artSide * 0.18, 10, 20) }

    /// Drop the album line first on a short panel (only room for title + artist).
    var showsAlbum: Bool { availableHeight >= 64 }

    // MARK: - Clock & calendar column

    /// Below this available height there is no room for a second column; the panel shows
    /// Now Playing full-width and the calendar is dropped entirely (never clipped).
    var showsCalendar: Bool { availableHeight >= 56 && panelSize.width >= 460 }
    /// Drop the weekday strip when the column is tight; keep just the clock + big date.
    var showsWeekStrip: Bool { availableHeight >= 92 }
    var calendarWidth: CGFloat { clamp(panelSize.width * 0.3, 150, 200) }

    var clockFont: CGFloat { clamp(availableHeight * 0.28, 18, 30) }
    var monthFont: CGFloat { clamp(availableHeight * 0.13, 11, 14) }
    var dayFont: CGFloat { clamp(availableHeight * 0.24, 18, 26) }
    var columnSpacingV: CGFloat { clamp(availableHeight * 0.1, 4, 14) }

    private func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(value, lo), hi)
    }
}

struct NotchView: View {

    /// Created in AppDelegate and injected, so this is `@ObservedObject`, not `@StateObject`.
    @ObservedObject var viewModel: NotchViewModel

    /// Convenience accessor for the current media snapshot.
    private var info: NowPlayingInfo { viewModel.nowPlaying.info }

    /// Collapsed bottom corner radius (the pill / bare notch keep their simple rounded
    /// bottom). The EXPANDED panel uses a plain `UnevenRoundedRectangle` (all corners CONVEX /
    /// rounded outward — modest top radii, larger bottom radii), defined inline in `body`.
    private let collapsedBottomRadius: CGFloat = 10

    /// How far the expanded panel's top corners flare outward (NotchNook look).
    static let flareRadius: CGFloat = 12

    /// Responsive sizes for the expanded content, derived from the current panel height so
    /// nothing is ever clipped as the panel is made thinner (down to the 90 pt minimum).
    private var metrics: PanelMetrics { PanelMetrics(panelSize: viewModel.panelSize,
                                                     contentTopInset: viewModel.contentTopInset) }

    var body: some View {
        let expanded = viewModel.isExpanded
        // Collapsed + enabled + any Now Playing app playing → the pill beside the notch.
        let pill = !expanded && viewModel.showsMusicActivity
        let panelSize = viewModel.panelSize
        let size = expanded ? panelSize : (pill ? viewModel.musicActivitySize : viewModel.notchSize)
        // EXPANDED → the body hangs below the notch with a CONVEX outward "wing" added on
        // each side of the notch: the top is flat & flush at the notch's top corners, then
        // bulges OUTWARD-and-down to the wider body (material added beside the notch, never
        // scooped in — so it can't render a gouged "coak" outline). Bottom corners are plain
        // convex fillets. COLLAPSED → the simple flat-top / rounded-bottom shape the pill and
        // bare notch use.
        let expandedShape = NotchPanelShape(
            flareRadius: Self.flareRadius,
            bottomRadius: 22
        )
        let collapsedShape = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: collapsedBottomRadius,
            bottomTrailingRadius: collapsedBottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )

        content
            // The ONLY top padding: inside the shape, so content clears the camera cutout.
            .padding(.top, viewModel.contentTopInset)
            // Keep content inside the body, clear of the flared top corners.
            .padding(.horizontal, metrics.horizontalPadding + Self.flareRadius)
            .padding(.bottom, metrics.bottomPadding)
            // Laid out at the full panel size at all times so it never reflows mid-morph;
            // the clip below reveals it as the shape grows.
            .frame(width: panelSize.width, height: panelSize.height, alignment: .top)
            .opacity(expanded ? 1 : 0)
            // The pill's wings, top-centred on the panel-sized frame, so after the `size`
            // frame + clip below they sit exactly beside the notch. Hidden while expanded.
            .overlay(alignment: .top) {
                MusicActivityWings(
                    info: info,
                    notchSize: viewModel.notchSize,
                    wingWidth: viewModel.musicWingWidth,
                    equalizerColor: viewModel.settings.equalizerColor,
                    isAnimating: pill
                )
                .opacity(pill ? 1 : 0)
            }
            // The black shape: notch- or pill-sized when collapsed, panel-sized when
            // expanded, top-anchored so it grows down/out of the notch. Pure black so the
            // panel fuses with the hardware notch into one shape.
            .frame(width: size.width, height: size.height, alignment: .top)
            .background {
                if expanded {
                    expandedShape.fill(Color.black)
                } else {
                    collapsedShape.fill(Color.black)
                }
            }
            .clipShape(expanded ? AnyShape(expandedShape) : AnyShape(collapsedShape))
            // Collapsed end state = fully invisible unless the music pill is showing; hover
            // is detected from the cursor position in screen space (NotchWindowController),
            // not by anything drawn here.
            .opacity(expanded || pill ? 1 : 0)
            .allowsHitTesting(expanded)
            // Pin to the window's top-center: the shape's top edge is y = 0 = screen top.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Outline of the hover zone: briefly while its Settings are being adjusted, and
            // permanently while collapsed if Settings → Show hover zone is on.
            .overlay(alignment: .top) {
                hoverZonePreview
                    .animation(.easeOut(duration: 0.2), value: showsHoverZoneOutline)
            }
            // Optional (Settings, off by default): a red dot just right of the notch while
            // collapsed and any message badge is showing. Purely visual.
            .overlay(alignment: .top) {
                collapsedBadgeDot
                    .animation(.easeOut(duration: 0.2), value: showsCollapsedBadgeDot)
            }
            // Full-bleed overlay: never let a reported safe area push the shape down.
            .ignoresSafeArea()
            .animation(viewModel.settings.animation, value: expanded)
            .animation(viewModel.settings.animation, value: pill)
    }

    // MARK: - Hover-zone preview

    /// Whether the hover-zone outline is drawn: for a moment after a Hover-area /
    /// Horizontal-offset change, or always while collapsed with Show hover zone on. Drawing
    /// works even though the collapsed window ignores mouse events.
    private var showsHoverZoneOutline: Bool {
        viewModel.showsHoverZonePreview || (viewModel.settings.showHoverZone && !viewModel.isExpanded)
    }

    /// The configured hover zone (Width × Height), outlined. The window is centred on the
    /// zone's centre and top-anchored at the screen top, so this sits exactly on the
    /// screen-space zone; parts behind the physical notch can't be seen. Purely visual.
    @ViewBuilder
    private var hoverZonePreview: some View {
        if showsHoverZoneOutline {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                )
                .frame(width: viewModel.hoverSize.width, height: viewModel.hoverSize.height)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    // MARK: - Collapsed message dot

    private var showsCollapsedBadgeDot: Bool {
        !viewModel.isExpanded && viewModel.settings.showCollapsedBadgeDot
            && !viewModel.messageBadges.badges.isEmpty
    }

    /// The window is centred at `screen.midX + offset` and the notch at `screen.midX`, so the
    /// dot's x offset from the window centre is the notch's right edge minus the offset.
    @ViewBuilder
    private var collapsedBadgeDot: some View {
        if showsCollapsedBadgeDot {
            let notch = viewModel.notchSize
            MessageBadgeDot()
                .offset(x: notch.width / 2 - CGFloat(viewModel.settings.horizontalOffset)
                            + 3 + MessageBadgeDot.size / 2,
                        y: (notch.height - MessageBadgeDot.size) / 2)
                .transition(.opacity)
        }
    }

    // MARK: - Content

    /// The expanded panel body: the Now Playing section on the LEFT and the live clock +
    /// calendar section on the RIGHT, separated by a subtle vertical divider — matching the
    /// NotchNook reference. Laid out as a SINGLE short row so it fits the slim panel; all
    /// sizes come from `metrics`, which scales with the panel height so nothing is clipped
    /// even at the 90 pt minimum. Both columns sit below the camera cutout thanks to the top
    /// padding applied in `body`.
    private var content: some View {
        HStack(alignment: .center, spacing: metrics.columnSpacing) {
            // LEFT: Now Playing (compact single row).
            Group {
                if info.hasMedia {
                    nowPlayingPanel
                } else {
                    nothingPlayingPanel
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if metrics.showsCalendar {
                // Subtle vertical divider between the two sections.
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)

                // RIGHT: live clock (ticking seconds) + today's date / mini-week.
                ClockCalendarView(settings: viewModel.settings, metrics: metrics)
                    .frame(width: metrics.calendarWidth, alignment: .topLeading)
            }

            // FAR RIGHT: Messages / WhatsApp badges, stacked. They live in the content row,
            // below the notch band, because clicks in the top strip of the screen are taken by
            // the macOS menu bar (Help, Window, …) and never reach the panel.
            if !viewModel.messageBadges.badges.isEmpty {
                MessageBadgesRow(badges: viewModel.messageBadges.badges,
                                 onOpen: { viewModel.collapseNow() })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// The compact Now Playing panel: album art beside the title/album/artist stack and the
    /// source app's icon on one row, with transport controls either beside it (slim panel)
    /// or beneath it (taller panel). Every size comes from `metrics` so it shrinks instead of
    /// being clipped as the panel height drops.
    private var nowPlayingPanel: some View {
        let m = metrics
        return HStack(spacing: m.artSpacing) {
            // Album art (placeholder when none), sized from the panel height.
            Group {
                if let artwork = info.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note")
                            .font(.system(size: m.artSide * 0.38))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: m.artSide, height: m.artSide)
            .clipShape(RoundedRectangle(cornerRadius: m.artCornerRadius, style: .continuous))

            // Title / album / artist stacked; text shrinks via minimumScaleFactor so it is
            // never clipped on a narrow/short panel.
            VStack(alignment: .leading, spacing: m.titleSpacing) {
                Text(info.displayTitle)
                    .font(.system(size: m.titleFont, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)

                if m.showsAlbum, let album = info.album, !album.isEmpty {
                    Text(album)
                        .font(.system(size: m.subtitleFont))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.tail)
                }

                if !info.displayArtist.isEmpty {
                    Text(info.displayArtist)
                        .font(.system(size: m.subtitleFont))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // Click artwork / title / artist → bring the playing app to the front.
            .contentShape(Rectangle())
            .onTapGesture { openPlayingApp() }
            .pointingHandCursor()

            // Transport controls beside the metadata (compact single-row layout).
            HStack(spacing: m.transportSpacing) {
                transportButton(system: "backward.fill", size: m.transportSide) { viewModel.nowPlaying.previous() }
                transportButton(system: info.isPlaying ? "pause.fill" : "play.fill",
                                size: m.transportSide + 4) { viewModel.nowPlaying.togglePlayPause() }
                transportButton(system: "forward.fill", size: m.transportSide) { viewModel.nowPlaying.next() }
            }
            .fixedSize()
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }

    /// Activates the app that is playing (Apple Music when the AppleScript path supplied
    /// the info without a bundle ID), then closes the panel.
    private func openPlayingApp() {
        guard info.hasMedia else { return }
        let bundleID = info.sourceBundleID
            ?? ((info.source == .appleMusicScript || info.title != nil) ? "com.apple.Music" : nil)
        guard let bundleID else { return }
        AppLauncher.activate(bundleID: bundleID)
        viewModel.collapseNow()
    }

    /// Tasteful placeholder shown in the expanded panel when nothing is playing.
    private var nothingPlayingPanel: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: metrics.subtitleFont + 7))
                .foregroundStyle(.white.opacity(0.6))
            Text("Nothing playing")
                .font(.system(size: metrics.subtitleFont, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
struct AppleMusicGlyph: View {
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
