//
//  MusicActivityView.swift
//  AgoyNotch
//
//  The collapsed "live activity" pill shown beside the hardware notch while Apple Music is
//  playing: the LEFT wing shows the album artwork (or an Apple-Music-style SF Symbol
//  stand-in — NOT Apple's logo asset), the middle under the notch is plain black, and the
//  RIGHT wing shows an animated equalizer. NotchView places these wings inside its single
//  black morphing shape, so the pill is the same shape that grows into the panel.
//
//  The equalizer is a pure function of `TimelineView(.animation)`'s date: no @State, no
//  Timer, nothing to tear down, and the timeline pauses itself when not animating (paused
//  media or expanded panel). Everything is rendered locally; no network.
//

import SwiftUI

/// The pill's left and right wings, laid out across the full pill width (notch + 2 wings).
struct MusicActivityWings: View {
    let info: NowPlayingInfo
    let notchSize: CGSize
    let wingWidth: CGFloat
    let equalizerColor: Color
    /// True only while the pill is on screen (playing + collapsed).
    let isAnimating: Bool

    var body: some View {
        HStack(spacing: 0) {
            leftWing
                .frame(width: wingWidth, height: notchSize.height)
            // Under the hardware notch: plain black (the shape's background).
            Color.clear
                .frame(width: notchSize.width, height: notchSize.height)
            EqualizerBars(maxHeight: notchSize.height * 0.5,
                          color: equalizerColor,
                          isAnimating: isAnimating)
                .frame(width: wingWidth, height: notchSize.height)
        }
        .allowsHitTesting(false)
    }

    /// Album artwork thumbnail, or the SF Symbol stand-in when there is none.
    @ViewBuilder
    private var leftWing: some View {
        let side = max(notchSize.height - 10, 8)
        if let artwork = info.artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            // SF Symbol `music.note` on a red/pink tile — a stand-in, not Apple's logo asset.
            AppleMusicGlyph(size: side)
        }
    }
}

/// Four thin rounded bars bouncing with staggered timing.
struct EqualizerBars: View {
    let maxHeight: CGFloat
    let color: Color
    let isAnimating: Bool

    private static let speeds: [Double] = [7.0, 9.3, 6.1, 8.2]   // rad/s
    private static let phases: [Double] = [0, 0.9, 1.7, 2.6]
    private static let barWidth: CGFloat = 3
    private static let spacing: CGFloat = 2.5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: Self.spacing) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: Self.barWidth, height: barHeight(i, t))
                }
            }
            .frame(height: maxHeight, alignment: .bottom)
        }
    }

    /// Bar height between 30 % and 100 % of `maxHeight`; a static 30 % when not animating.
    private func barHeight(_ i: Int, _ t: Double) -> CGFloat {
        guard isAnimating else { return maxHeight * 0.3 }
        let wave = 0.5 + 0.5 * sin(t * Self.speeds[i] + Self.phases[i])
        return maxHeight * CGFloat(0.3 + 0.7 * wave)
    }
}
