//
//  VisualEffectView.swift
//  MacNotch
//
//  Thin SwiftUI wrapper around NSVisualEffectView so the expanded notch panel can place a
//  frosted-glass backdrop behind its content.
//

import SwiftUI
import AppKit

/// Bridges `NSVisualEffectView` into SwiftUI.
struct VisualEffectView: NSViewRepresentable {
    typealias NSViewType = NSVisualEffectView

    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}
