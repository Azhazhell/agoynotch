//
//  SystemStatsTopRow.swift
//  AgoyNotch
//
//  The expanded panel's top row, level with the camera: CPU % right-aligned against the
//  camera's LEFT edge and RAM used left-aligned against its RIGHT edge. Numbers only — no
//  labels, no icons. Purely visual (clicks in the menu-bar strip go to the menu bar).
//

import SwiftUI

struct SystemStatsTopRow: View {
    @ObservedObject var stats: SystemStatsMonitor
    let panelWidth: CGFloat
    let notchSize: CGSize
    /// Width of the panel's black band left / right of the camera (see NotchViewModel).
    let leftBandWidth: CGFloat
    let rightBandWidth: CGFloat

    /// Gap between the text and the camera cutout's edge.
    static let cameraGap: CGFloat = 8

    private var fontSize: CGFloat { min(max(notchSize.height * 0.38, 10), 13) }

    var body: some View {
        let leftW = max(leftBandWidth - Self.cameraGap, 0)
        let rightW = max(rightBandWidth - Self.cameraGap, 0)
        HStack(spacing: 0) {
            // CPU: right-aligned against the camera's left edge.
            label(stats.cpuText)
                .frame(width: leftW, alignment: .trailing)
            // The camera (notch width + a gap on each side): kept empty.
            Color.clear
                .frame(width: max(panelWidth - leftW - rightW, 0))
            // RAM: left-aligned against the camera's right edge.
            label(stats.ramText)
                .frame(width: rightW, alignment: .leading)
        }
        // Menu-bar-height strip; text is vertically centred in it.
        .frame(width: panelWidth, height: notchSize.height)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(Font.system(size: fontSize, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}
