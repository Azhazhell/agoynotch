// swift-tools-version:6.0
// The tools-version comment above MUST be the very first line of the manifest.
// tools-version 6.0 ships with Xcode 16+ and is valid on Xcode 27 / the macOS 27 SDK.
// It is required so that the `.macOS(.v15)` platform enum below is recognized —
// older tools-versions (e.g. 5.9) report "'v15' is unavailable" because that enum
// case did not exist yet in their PackageDescription.

import PackageDescription

let package = Package(
    name: "AgoyNotch",
    // Deployment target macOS 15.0: every API this app uses (NSPanel, SMAppService,
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
            // Resources/Info.plist and scripts/build-app.sh live outside this path, so the
            // target never sees them; the script uses them to assemble AgoyNotch.app.
            path: "Sources/AgoyNotch",
            // Pin the Swift language mode to 5. tools-version 6.0 would otherwise default
            // to the Swift 6 language mode, whose *strict concurrency* checking turns
            // ordinary AppKit/Combine patterns (passing `self` into NotificationCenter
            // observer closures, @escaping C callbacks) into hard errors like
            // "Sending 'self' risks causing data races". This app is single-UI-thread by
            // design, so language mode 5 keeps the long-standing, correct behavior while
            // still letting us use tools-version 6.0 (needed for `.macOS(.v15)`).
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
