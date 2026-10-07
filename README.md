# AgoyNotch

Turn your MacBook's hardware camera notch into a Dynamic Island–style interactive surface.

AgoyNotch sits flush under the real notch as a thin, nearly invisible pill. When media is
playing it shows a tiny album-art thumbnail and an animated audio-bars indicator. Hover the
notch and it expands downward with a spring animation into a Now Playing panel — album art,
title, artist, and prev / play-pause / next transport controls — then collapses when you move
away. It is a native macOS app written in Swift (AppKit + SwiftUI), with **no third-party
dependencies**.

> **Why this exists:** closed-source "notch" utilities ask you to trust a binary. AgoyNotch is
> the opposite — the entire source is here, it makes **no network calls** and collects **no
> telemetry**. Everything runs locally on your Mac.

```
┌───────────────[ ● notch ● ]───────────────┐   ← collapsed pill hugging the notch
                      │ hover
                      ▼
        ┌──────────────────────────────┐
        │  🎵  Song Title               │       ← expanded Now Playing panel
        │      Artist      ⏮  ⏯  ⏭      │
        └──────────────────────────────┘
```

*(Screenshot placeholder — add a real capture here once you build and run.)*

## Requirements

- An Apple Silicon MacBook **with a hardware notch** (e.g. MacBook Air M2, 2022). On Macs
  without a notch the app still runs and anchors a pill to the top-center of the main display.
- macOS 15.0 or later. Built and tested against the macOS 27 ("Golden Gate") SDK.
- Xcode 27.

## Build & Run

This is a Swift Package Manager **executable** package (text-only `Package.swift`, no
`.xcodeproj`), which opens and builds reliably in Xcode.

1. Open the manifest in Xcode:
   `/projects/sandbox/MacNotch/Package.swift`
2. Select the **My Mac** run destination.
3. Press **Run** (⌘R).

The app launches with **no Dock icon**. Look for the AgoyNotch icon in the **menu bar**, and for
the pill under your notch.

## Adjusting the notch

AgoyNotch auto-detects your hardware notch geometry and anchors the overlay flush under it.
On some Macs the overlay can sit a hair off from the physical notch, so you can fine-tune it
from the **menu bar → Adjust Notch** submenu:

- **Move Left** / **Move Right** — shift the overlay horizontally (±2 pt per click).
- **Move Down** / **Move Up** — nudge the overlay vertically from the top edge (±2 pt).
- **Wider** / **Narrower** — grow or shrink the collapsed pill's width (±2 pt).
- **Reset Position** — clear all adjustments back to the pure auto-detected geometry.

Each click repositions the overlay immediately, and your adjustments are **saved and restored
across launches** (stored locally in `UserDefaults` — no network, no telemetry).

## Permissions & signing

AgoyNotch reads Now Playing information through Apple's **private** `MediaRemote` framework,
loaded at runtime with `dlopen`/`dlsym`. Because of that:

- **Run it locally from Xcode** (or sign it ad-hoc). The App Sandbox blocks loading private
  frameworks, so there is no sandbox entitlement here — build & run on your own Mac.
- **macOS 15.4+ caveat.** Since macOS 15.4 the system `mediaremoted` daemon verifies caller
  entitlements before handing back Now Playing data. On macOS 27 an unentitled build may
  therefore receive **empty** info even though the framework loaded fine. When that happens the
  panel honestly shows **"Nothing playing"** rather than guessing.
  - **Fallback / workaround:** drive media through the Control Center media widget, and watch
    this repo's roadmap for an alternative adapter (e.g. a scripting-based bridge) that does not
    depend on the private daemon returning data to unentitled callers.

## App Store note

Because AgoyNotch uses a **private Apple framework**, it is **not eligible for the Mac App
Store**. For distribution outside the store, notarize the signed app; for personal use, running
straight from Xcode is enough.

## Privacy

- **No network calls.** There is no `URLSession`, no sockets, nothing phones home.
- **No telemetry.** Nothing is logged off-device.
- **Fully local & transparent.** The only system component AgoyNotch talks to is the on-device
  media daemon, via the open source in this repository.

## How to quit

Click the **AgoyNotch menu-bar icon → Quit AgoyNotch** (⌘Q while the menu is open).

## Roadmap

The MVP is intentionally focused on Now Playing + hover-expand, but the code is structured so
these can be added as additional "modes" of the notch surface:

- **Clipboard shelf** — recent clipboard items parked under the notch.
- **File drop shelf** — drag files onto the notch to stage them.
- **Battery / charging HUD** — a glance at charge state and time remaining.
- **Timers** — quick countdowns surfaced in the island.
- **Notifications** — compact notification previews in the expanded panel.

## Project layout

```
AgoyNotch/
  Package.swift                       SPM manifest (macOS 15 target, one executable target)
  README.md
  .gitignore
  Sources/AgoyNotch/
    AgoyNotchApp.swift                @main; NSApplicationDelegateAdaptor → AppDelegate
    AppDelegate.swift                 accessory policy, object graph, menu-bar item + Adjust/Quit
    NotchSettings.swift               persisted manual offsets (UserDefaults) over auto-geometry
    NotchWindow.swift                 borderless non-activating NSPanel + hover tracking area
    NotchWindowController.swift       notch geometry + placement + resize on expand/collapse
    NotchViewModel.swift              expand/collapse state, hover debounce, panel sizes
    NotchView.swift                   SwiftUI collapsed pill + expanded Now Playing panel
    VisualEffectView.swift            NSVisualEffectView frosted-glass backdrop
    NowPlaying/
      NowPlayingInfo.swift            plain media data model
      MediaRemoteBridge.swift         isolated private-MediaRemote dlopen/dlsym boundary
      NowPlayingManager.swift         observable Now Playing service + transport commands
```
