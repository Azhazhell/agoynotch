# AgoyNotch

Turn your MacBook's hardware camera notch into a Dynamic Island–style interactive surface.

AgoyNotch merges with the real hardware notch: when idle the collapsed overlay is a black
shape anchored to the top of the screen at the notch's height, so it reads as a single
continuous notch rather than a second box below it. While Apple Music is playing it shows a
small music glyph just left of the notch and an animated equalizer just right. Hover the
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
   `/projects/sandbox/agoynotch/Package.swift`
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
- **Wider** / **Narrower** — grow or shrink the collapsed shape's width (±2 pt).
- **Taller** / **Shorter** — grow or shrink the collapsed shape's height / vertical
  coverage (±2 pt), so you can make the black overlay exactly cover your real notch.
- **Reset Position** — clear all adjustments (horizontal, vertical, width, height) back to
  the pure auto-detected geometry.

The collapsed overlay is designed to **merge with the hardware notch**: its top edge is
anchored to the physical top of the display and its height matches the notch height
(`NSScreen.safeAreaInsets.top`), with flat top corners so it reads as one continuous notch
rather than a second black box hanging below. A small music glyph sits just left of the
notch and an animated equalizer just right. If the seam is a hair off on your Mac, use
**Taller/Shorter** and **Wider/Narrower** to dial it in.

Each click repositions the overlay immediately, and your adjustments are **saved and restored
across launches** (stored locally in `UserDefaults` — no network, no telemetry).

## Now Playing & permissions

**Now Playing uses AppleScript to Apple Music** (`Music.app`). AgoyNotch polls Music's
`player state` and the current track's name / artist / album, and reads album art as raw
local image bytes via `data of artwork 1 of current track`. Apple Music works best; this is
the live data source on macOS 27.

- **Grant Automation permission on first run.** The first time AgoyNotch sends an AppleScript
  command to Music, macOS shows an **Automation** consent prompt — click **OK / Allow**. You
  can review or re-enable it later under **System Settings → Privacy & Security → Automation**.
  If you deny it, the panel honestly shows **"Nothing playing"** instead of crashing.
- **Unbundled executable caveat.** Because this ships as a Swift Package Manager executable
  (no real `.app` bundle / `Info.plist`), the Automation prompt can be flaky or may not persist
  reliably. The proper fix is to run AgoyNotch as a **bundled, signed `.app`** so macOS can
  attach the Automation grant to a stable bundle identifier. Until then, every AppleScript call
  degrades gracefully: if Music isn't running or the script isn't authorized (error `-1743`),
  AgoyNotch logs a concise message and shows "Nothing playing".
- **Graceful behavior.** If Music is stopped, not running, or unauthorized, the panel shows
  "Nothing playing" — it never forces Music to launch just to query it.

### Why AppleScript (historical MediaRemote note)

Earlier builds read Now Playing through Apple's **private** `MediaRemote` framework
(`dlopen`/`dlsym`; see `MediaRemoteBridge.swift`, kept as dormant historical code). Since
**macOS 15.4** the system `mediaremoted` daemon verifies caller entitlements before handing
back Now Playing data, so on **macOS 27** an unentitled build receives **empty** info and the
panel always read "Nothing playing". AppleScript to a scriptable player still works, so it is
now the live source. `MediaRemoteBridge` remains in the tree only to document that path.

## App Store & signing note

Running straight from Xcode on your own Mac is enough for personal use. The dormant
`MediaRemoteBridge` uses a **private Apple framework**, which is **not eligible for the Mac
App Store**; for distribution outside the store, notarize a signed, bundled `.app` (which
also makes the Automation permission for Apple Music persist reliably).

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
      AppleScriptNowPlaying.swift     LIVE source: AppleScript → Apple Music (status + transport)
      MediaRemoteBridge.swift         dormant historical private-MediaRemote dlopen/dlsym boundary
      NowPlayingManager.swift         observable Now Playing service (polls AppleScript) + transport
```
