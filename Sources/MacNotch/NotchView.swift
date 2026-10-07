//
//  NotchView.swift
//  MacNotch
//
//  The SwiftUI surface rendered inside the notch panel. It morphs between a thin collapsed
//  pill hugging the real notch and an expanded Dynamic-Island-style Now Playing panel.
//  The container is a black rounded shape whose BOTTOM corners are more rounded than the
//  top, to mimic the hardware notch / Dynamic Island.
//

import SwiftUI

struct NotchView: View {

    /// Created in AppDelegate and injected, so this is `@ObservedObject`, not `@StateObject`.
    @ObservedObject var viewModel: NotchViewModel

    /// Convenience accessor for the current media snapshot.
    private var info: NowPlayingInfo { viewModel.nowPlaying.info }

    // Corner radii: bottom corners rounder than the top for the notch look.
    private let topCornerRadius: CGFloat = 8
    private let bottomCornerRadius: CGFloat = 22

    var body: some View {
        ZStack {
            container
        }
        // Fill the window; the window itself is sized by the controller.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isExpanded)
    }

    // MARK: - Container

    private var container: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: topCornerRadius,
            bottomLeadingRadius: bottomCornerRadius,
            bottomTrailingRadius: bottomCornerRadius,
            topTrailingRadius: topCornerRadius,
            style: .continuous
        )

        return ZStack {
            // Frosted backdrop only when expanded; collapsed stays near-pure black so it
            // blends into the physical notch.
            if viewModel.isExpanded {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.55)
            } else {
                Color.black
            }

            content
                .padding(.horizontal, viewModel.isExpanded ? 14 : 8)
                .padding(.vertical, viewModel.isExpanded ? 12 : 2)
        }
        .clipShape(shape)
        .frame(
            width: viewModel.isExpanded ? viewModel.expandedSize.width : viewModel.collapsedSize.width,
            height: viewModel.isExpanded ? viewModel.expandedSize.height : viewModel.collapsedSize.height
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isExpanded {
            expandedContent
        } else {
            collapsedContent
        }
    }

    // MARK: Collapsed

    private var collapsedContent: some View {
        HStack {
            // Tiny album-art thumbnail on the left when something is playing.
            if info.hasMedia, let artwork = info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            Spacer(minLength: 0)

            // Animated audio bars on the right, only while actively playing.
            if info.isPlaying {
                AudioBarsView()
                    .frame(width: 16, height: 14)
            }
        }
        // When nothing is playing the pill is near-invisible against the physical notch.
        .opacity(info.hasMedia ? 1 : 0.001)
    }

    // MARK: Expanded

    private var expandedContent: some View {
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
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // Title / artist / transport controls.
            VStack(alignment: .leading, spacing: 6) {
                Text(info.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(info.displayArtist)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                HStack(spacing: 18) {
                    transportButton(system: "backward.fill") { viewModel.nowPlaying.previous() }
                    transportButton(system: info.isPlaying ? "pause.fill" : "play.fill",
                                    size: 18) { viewModel.nowPlaying.togglePlayPause() }
                    transportButton(system: "forward.fill") { viewModel.nowPlaying.next() }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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

// MARK: - Animated audio bars

/// Three bars whose heights oscillate to signal active playback. Purely decorative.
private struct AudioBarsView: View {
    @State private var animating = false

    private let barCount = 3

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3)
                    .scaleEffect(y: animating ? 1.0 : 0.35, anchor: .center)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { animating = true }
    }
}
