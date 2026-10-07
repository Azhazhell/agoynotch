//
//  NotchView.swift
//  AgoyNotch
//
//  The SwiftUI surface rendered inside the notch panel. It morphs between a thin collapsed
//  pill hugging the real notch and an expanded Dynamic-Island-style Now Playing panel.
//  The container is a black rounded shape whose BOTTOM corners are more rounded than the
//  top, to mimic the hardware notch / Dynamic Island.
//
//  Fixed-window note: the NSWindow is permanently the EXPANDED size (see
//  NotchViewModel.windowSize). This view therefore draws its content TOP-ANCHORED inside
//  that fixed frame — the collapsed pill hugs the top (over the hardware notch) and the
//  expanded panel "hangs" just below it. The surrounding area is transparent. Keeping the
//  window a constant size is what makes the hover tracking area cover the whole panel, so
//  the cursor can reach the transport buttons without collapsing the panel.
//

import SwiftUI

struct NotchView: View {

    /// Created in AppDelegate and injected, so this is `@ObservedObject`, not `@StateObject`.
    @ObservedObject var viewModel: NotchViewModel

    /// Convenience accessor for the current media snapshot.
    private var info: NowPlayingInfo { viewModel.nowPlaying.info }

    // Corner radii. The COLLAPSED shape keeps its TOP corners flat/minimal and only its
    // BOTTOM corners rounded, so it reads as a seamless continuation of the hardware notch
    // (whose own top edge is the flat top of the screen). The expanded panel is rounded on
    // all four corners like a Dynamic-Island card.
    private let collapsedTopCornerRadius: CGFloat = 0
    private let collapsedBottomCornerRadius: CGFloat = 10
    private let expandedTopCornerRadius: CGFloat = 10
    private let expandedBottomCornerRadius: CGFloat = 22

    var body: some View {
        // Top-anchored inside the fixed (expanded-sized) window. Only the container paints;
        // everything around it is transparent (and non-interactive for clicks via the
        // hosting view's hitTest).
        //
        // When COLLAPSED the container sits flush at the very top (y = 0 in SwiftUI's
        // top-left space) so its black merges with the hardware notch. When EXPANDED we push
        // the card DOWN by the notch height so the Dynamic-Island panel "hangs" just below
        // the physical notch instead of overlapping it. The push is animated with the same
        // spring as the morph.
        container
            .padding(.top, viewModel.isExpanded ? viewModel.collapsedSize.height : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // "Hangs below the notch" fix: ignore the safe area so SwiftUI does NOT inset
            // this content below the hardware notch / menu bar. Combined with the hosting
            // view returning zero `safeAreaInsets` (see NotchHostingView), this guarantees
            // the top-anchored collapsed pill's top edge sits at the physical top of the
            // display and fuses with the real notch instead of hanging below it.
            .ignoresSafeArea(.all)
            // Spring morph between collapsed and expanded, like Dynamic Island. The window
            // never resizes — only this SwiftUI content grows/shrinks.
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isExpanded)
    }

    // MARK: - Container

    private var container: some View {
        // Pick corner radii per state: flat top while collapsed (so it merges with the
        // hardware notch), fully rounded while expanded.
        let topRadius = viewModel.isExpanded ? expandedTopCornerRadius : collapsedTopCornerRadius
        let bottomRadius = viewModel.isExpanded ? expandedBottomCornerRadius : collapsedBottomCornerRadius
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )

        return ZStack {
            // Collapsed END state = COMPLETELY INVISIBLE. The user wants to see only their
            // real, untouched hardware notch when idle, so we draw NOTHING while collapsed —
            // no black pill, no Apple-Music glyph, no equalizer, no shape at all. We keep a
            // transparent `Color.clear` placeholder so the container still has a defined
            // frame (which the layout and the top padding above rely on); it paints nothing.
            //
            // Frosted backdrop + content are drawn ONLY when expanded. Hover detection does
            // not depend on anything painted here: it is driven by the NSTrackingArea in
            // NotchHostingView, which stays positioned over the physical notch even while
            // this collapsed state paints nothing (drawing is decoupled from tracking).
            if viewModel.isExpanded {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.55)

                content
                    // Expanded padding only; the collapsed branch draws nothing.
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            } else {
                // Nothing visible when collapsed.
                Color.clear
            }
        }
        .clipShape(shape)
        .frame(
            width: viewModel.isExpanded ? viewModel.expandedSize.width : viewModel.collapsedSize.width,
            height: viewModel.isExpanded ? viewModel.expandedSize.height : viewModel.collapsedSize.height
        )
    }

    // MARK: - Content

    /// Content painted inside the container. Only the EXPANDED panel is ever shown; the
    /// collapsed state is fully invisible (see `container`, which draws `Color.clear` while
    /// collapsed and never calls this). `collapsedContent` below is retained for reference
    /// but is intentionally no longer rendered.
    @ViewBuilder
    private var content: some View {
        expandedContent
    }

    // MARK: Collapsed (retained, no longer rendered)

    /// Minimal pill hugging the hardware notch: an Apple-Music-style glyph on the left and
    /// an animated equalizer on the right.
    ///
    /// NOTE: this is intentionally NOT rendered anymore. The collapsed state is now fully
    /// invisible (`container` paints `Color.clear`), per the user's decision to show only
    /// the real hardware notch when idle. Kept here for reference / possible future use.
    private var collapsedContent: some View {
        HStack(spacing: 0) {
            // LEFT: Apple-Music-style activity glyph.
            AppleMusicGlyph(size: 14)
                .opacity(info.hasMedia ? 1 : 0)

            Spacer(minLength: 0)

            // RIGHT: animated equalizer; animates only while actively playing, otherwise
            // rests short and static.
            EqualizerView(isPlaying: info.isPlaying)
                .frame(width: 16, height: 12)
                .opacity(info.hasMedia ? 1 : 0)
        }
    }

    // MARK: Expanded

    @ViewBuilder
    private var expandedContent: some View {
        if info.hasMedia {
            nowPlayingPanel
        } else {
            nothingPlayingPanel
        }
    }

    /// The full Now Playing panel: artwork, title/album/artist, Apple-Music glyph, and the
    /// transport controls.
    private var nowPlayingPanel: some View {
        HStack(spacing: 12) {
            // Album art (placeholder when none).
            Group {
                if let artwork = info.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        Image(systemName: "music.note")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Title / album / artist stacked, matching the reference.
            VStack(alignment: .leading, spacing: 2) {
                Text(info.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let album = info.album, !album.isEmpty {
                    Text(album)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                if !info.displayArtist.isEmpty {
                    Text(info.displayArtist)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Small Apple-Music-style glyph before the transport controls.
            AppleMusicGlyph(size: 15)

            // Transport controls. These stay wired to the view model's transport methods.
            HStack(spacing: 14) {
                transportButton(system: "backward.fill") { viewModel.nowPlaying.previous() }
                transportButton(system: info.isPlaying ? "pause.fill" : "play.fill",
                                size: 18) { viewModel.nowPlaying.togglePlayPause() }
                transportButton(system: "forward.fill") { viewModel.nowPlaying.next() }
            }
        }
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

// MARK: - Animated equalizer

/// A small equalizer: thin vertical bars that bounce continuously while media is playing
/// and rest short and static when paused or nothing is playing. Purely decorative.
private struct EqualizerView: View {
    /// Drives whether the bars animate. When false the bars sit at their resting height.
    var isPlaying: Bool

    @State private var animating = false

    private let barCount = 4
    // Per-bar resting (paused) scale and animation timing, staggered so the bars look lively.
    private let restingScale: CGFloat = 0.3

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2.5)
                    .scaleEffect(y: (animating && isPlaying) ? 1.0 : restingScale, anchor: .center)
                    .animation(
                        isPlaying
                            ? .easeInOut(duration: 0.45)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.12)
                            : .easeOut(duration: 0.2),
                        value: animating && isPlaying
                    )
            }
        }
        .frame(maxHeight: .infinity)
        // Kick off the repeating bounce once the view appears; the `isPlaying` gate in the
        // scaleEffect/animation above decides whether it actually moves or rests.
        .onAppear { animating = true }
    }
}
