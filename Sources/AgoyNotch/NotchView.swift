//
//  NotchView.swift
//  AgoyNotch
//
//  The SwiftUI surface rendered inside the notch panel. It morphs between a fully invisible
//  collapsed state (nothing drawn, so the user sees only their real hardware notch) and an
//  expanded Now Playing panel that GROWS OUT OF the physical notch — NotchNook / Dynamic
//  Island style.
//
//  NotchNook feel (the point of this file): when expanded, the panel's TOP edge is flush
//  with the physical top of the display (y = 0 in SwiftUI's top-left space, which the window
//  pins to screen.frame.maxY — see NotchWindowController). The top band of the panel is as
//  WIDE AS THE HARDWARE NOTCH with FLAT top corners, so it reads as a continuation of the
//  real notch; the panel then flares DOWNWARD and OUTWARD (wider than the notch) with
//  rounded BOTTOM corners. Together with the hardware notch this is one continuous black
//  shape that appears to "open" out of the notch — NOT a separate floating box hanging below
//  it with a gap.
//
//  Fixed-window note: the NSWindow is permanently the EXPANDED size (see
//  NotchViewModel.windowSize). This view draws its content TOP-ANCHORED inside that fixed
//  frame. The collapsed state paints nothing; the expanded panel fills the window from the
//  very top down. Keeping the window a constant size is what makes the hover tracking area
//  cover the whole panel, so the cursor can reach the transport buttons without collapsing.
//

import SwiftUI

struct NotchView: View {

    /// Created in AppDelegate and injected, so this is `@ObservedObject`, not `@StateObject`.
    @ObservedObject var viewModel: NotchViewModel

    /// Convenience accessor for the current media snapshot.
    private var info: NowPlayingInfo { viewModel.nowPlaying.info }

    /// Corner radius of the panel's rounded BOTTOM corners when expanded. The TOP corners
    /// are always FLAT (radius 0) so the panel's top edge fuses seamlessly with the flat top
    /// bezel of the display / hardware notch — exactly like NotchNook.
    private let expandedBottomCornerRadius: CGFloat = 22

    /// Radius of the small shoulders where the narrow notch-width top band flares out into
    /// the wider panel body. Purely cosmetic smoothing of the "opening" curve.
    private let shoulderRadius: CGFloat = 10

    var body: some View {
        // Top-anchored inside the fixed (expanded-sized) window. Only the container paints;
        // everything around it is transparent (and non-interactive for clicks via the
        // hosting view's hitTest).
        //
        // The panel's TOP edge sits at y = 0 (the window top), which the controller pins to
        // the physical top of the display, so the panel grows straight out of the hardware
        // notch with NO gap above it.
        container
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Safe-area fix: ignore the safe area so SwiftUI does NOT inset this content
            // below the hardware notch / menu bar. Combined with the hosting view returning
            // zero `safeAreaInsets` (see NotchHostingView), this guarantees the panel's top
            // edge sits at the physical top of the display and fuses with the real notch
            // instead of hanging below it.
            .ignoresSafeArea(.all)
            // Spring morph between collapsed and expanded, like Dynamic Island. The window
            // never resizes — only this SwiftUI content grows/shrinks. The scale is anchored
            // at the TOP so the panel appears to grow DOWN/OUT of the notch and collapse
            // back INTO it.
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isExpanded)
    }

    // MARK: - Container

    @ViewBuilder
    private var container: some View {
        if viewModel.isExpanded {
            expandedPanel
                // GROW OUT OF THE NOTCH: the panel scales up from a notch-sized seed at the
                // top center into its full size, anchored at the TOP so it unfolds downward
                // and outward. Combined with the spring on `body`, the panel appears to
                // emerge from the hardware notch; collapsing reverses the scale back into the
                // notch and then the view disappears (collapsed draws nothing).
                .transition(.scale(scale: notchScale, anchor: .top).combined(with: .opacity))
        } else {
            // Collapsed END state = COMPLETELY INVISIBLE. The user wants to see only their
            // real, untouched hardware notch when idle, so we draw NOTHING while collapsed —
            // no black shape at all. Hover detection does not depend on anything painted
            // here: it is driven by the NSTrackingArea in NotchHostingView, which stays
            // positioned over the physical notch even while this collapsed state paints
            // nothing (drawing is decoupled from tracking).
            Color.clear
                .frame(width: 1, height: 1)
        }
    }

    /// The initial scale of the expanded panel's grow-out transition: the ratio of the
    /// notch-width seed to the full expanded width. Keeps the "unfold from the notch" start
    /// roughly notch-sized rather than a generic shrink-to-point.
    private var notchScale: CGFloat {
        let full = viewModel.expandedSize.width
        guard full > 0 else { return 0.3 }
        return max(0.1, min(1, viewModel.collapsedSize.width / full))
    }

    // MARK: - Expanded panel (one continuous shape with the hardware notch)

    private var expandedPanel: some View {
        // The outline that fuses with the hardware notch: FLAT top corners, a notch-width
        // top band, flaring out to a wider body with ROUNDED bottom corners. The hardware
        // notch sits exactly over the top band, so screen + panel read as one black shape.
        let shape = NotchPanelShape(
            topBandWidth: topBandWidth,
            topBandHeight: viewModel.notchInset,
            bottomCornerRadius: expandedBottomCornerRadius,
            shoulderRadius: shoulderRadius
        )

        return ZStack {
            // Frosted backdrop + near-black fill so the body matches the pure black of the
            // hardware notch at the top band and darkens the frost below.
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            Color.black.opacity(0.55)

            // Content lives in the LOWER / WIDER part of the panel, below the notch-width top
            // band, so nothing is hidden behind the physical notch cutout. The top inset
            // equals the notch height plus a little breathing room; horizontal insets leave
            // the body clear of the real notch cutout.
            content
                .padding(.top, viewModel.notchInset + 10)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
        }
        .frame(width: viewModel.expandedSize.width,
               height: viewModel.expandedSize.height)
        .clipShape(shape)
    }

    /// Width of the panel's top band. It matches the collapsed/notch width so the band is as
    /// wide as the hardware notch and disappears beneath it, leaving only the wider body
    /// visible below — exactly the NotchNook "grows out of the notch" silhouette.
    private var topBandWidth: CGFloat {
        min(viewModel.collapsedSize.width, viewModel.expandedSize.width)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if info.hasMedia {
            nowPlayingPanel
        } else {
            nothingPlayingPanel
        }
    }

    /// The full Now Playing panel, laid out for the taller NotchNook-sized body: a top row
    /// with the (large) album art beside the title/album/artist stack and an Apple-Music
    /// glyph, and a row of transport controls beneath — all comfortably below the notch band.
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

// MARK: - NotchNook-style panel outline

/// The outline that makes the expanded panel read as one continuous black shape with the
/// hardware notch. It has:
///   • a FLAT top edge (top corners radius 0) flush with the display's top bezel,
///   • a top BAND exactly as wide as the hardware notch (`topBandWidth` × `topBandHeight`),
///     which sits beneath the real notch and so is hidden by it,
///   • shoulders that flare OUT from the band to the full (wider) panel width,
///   • rounded BOTTOM corners.
/// Drawn top-anchored in a non-flipped-agnostic way: the path is built in SwiftUI's local
/// top-left coordinate space (`Path`/`Shape` are always top-left), so y increases downward.
private struct NotchPanelShape: Shape {
    /// Width of the notch-width top band (centered horizontally).
    var topBandWidth: CGFloat
    /// Height of the top band (the hardware notch height). The flare to full width happens
    /// just below this.
    var topBandHeight: CGFloat
    /// Radius of the panel's bottom corners.
    var bottomCornerRadius: CGFloat
    /// Radius of the shoulders where the band flares out to full width.
    var shoulderRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let fullLeft = rect.minX
        let fullRight = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY

        // Clamp the band so it never exceeds the full width.
        let bandW = min(topBandWidth, rect.width)
        let bandLeft = rect.midX - bandW / 2
        let bandRight = rect.midX + bandW / 2
        let bandBottom = min(top + topBandHeight, bottom)

        let shoulder = min(shoulderRadius, (rect.width - bandW) / 2, max(0, bandBottom - top))
        let bottomR = min(bottomCornerRadius, rect.width / 2, max(0, bottom - bandBottom))

        // Start at the top-left of the band (flat top edge over the notch).
        path.move(to: CGPoint(x: bandLeft, y: top))
        // Flat top edge across the band to the top-right of the band.
        path.addLine(to: CGPoint(x: bandRight, y: top))
        // Down the right side of the band to just above the shoulder.
        path.addLine(to: CGPoint(x: bandRight, y: bandBottom - shoulder))
        // Right shoulder: curve outward to the full right edge.
        path.addQuadCurve(
            to: CGPoint(x: bandRight + shoulder, y: bandBottom),
            control: CGPoint(x: bandRight, y: bandBottom)
        )
        // Across the (horizontal) shoulder step to the full right edge.
        path.addLine(to: CGPoint(x: fullRight, y: bandBottom))
        // Down the full right edge to the bottom-right corner.
        path.addLine(to: CGPoint(x: fullRight, y: bottom - bottomR))
        path.addQuadCurve(
            to: CGPoint(x: fullRight - bottomR, y: bottom),
            control: CGPoint(x: fullRight, y: bottom)
        )
        // Across the bottom edge to the bottom-left corner.
        path.addLine(to: CGPoint(x: fullLeft + bottomR, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: fullLeft, y: bottom - bottomR),
            control: CGPoint(x: fullLeft, y: bottom)
        )
        // Up the full left edge to the left shoulder.
        path.addLine(to: CGPoint(x: fullLeft, y: bandBottom))
        path.addLine(to: CGPoint(x: bandLeft - shoulder, y: bandBottom))
        // Left shoulder: curve inward up to the band.
        path.addQuadCurve(
            to: CGPoint(x: bandLeft, y: bandBottom - shoulder),
            control: CGPoint(x: bandLeft, y: bandBottom)
        )
        // Up the left side of the band back to the start.
        path.addLine(to: CGPoint(x: bandLeft, y: top))
        path.closeSubpath()

        return path
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
