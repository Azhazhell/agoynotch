// swift-tools-version:5.9
// The tools-version comment above MUST be the very first line of the manifest.
// swift-tools-version:5.9 ships with Xcode 15+ and remains valid on the macOS 27 SDK / Xcode 27.

import PackageDescription

let package = Package(
    name: "AgoyNotch",
    // Deployment target macOS 15.0: every API this app uses (NSPanel, NSVisualEffectView,
    // NSScreen.safeAreaInsets / auxiliaryTopLeftArea / auxiliaryTopRightArea, SwiftUI,
    // dlopen/dlsym, UnevenRoundedRectangle) has existed since macOS 12–13, so this builds
    // cleanly on the macOS 27 SDK without any invented macOS-27-only API.
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        // A single executable target. The target name "AgoyNotch" matches the source
        // directory Sources/AgoyNotch. No third-party dependencies — everything is local-only.
        .executableTarget(
            name: "AgoyNotch",
            path: "Sources/AgoyNotch"
        )
    ]
)
