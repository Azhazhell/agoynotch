# AgoyNotch

Turn your MacBook's hardware camera notch into a Dynamic Island–style interactive surface.

When idle AgoyNotch draws **nothing** — you see only your real notch. Move the cursor onto
the notch and a black panel grows out of it with a spring animation: one continuous black
shape whose top edge is the very top of the screen (it covers the notch and the menu-bar
strip beside it), with the content laid out just below the camera cutout. The panel shows
Apple Music's Now Playing (album art, title, album, artist, prev / play-pause / next) and,
beside it, a **live clock (ticking every second) and a compact calendar**. Move away and it
shrinks back into the notch. It is a native macOS app written in Swift (AppKit + SwiftUI),
with **no third-party dependencies**.

> **Why this exists:** closed-source "notch" utilities ask you to trust a binary. AgoyNotch is
> the opposite — the entire source is here, it makes **no network calls** and collects **no
> telemetry**. Everything runs locally on your Mac.

```
███████████████[   notch   ]███████████████   ← top edge = top of the screen
█  🎵  Song Title        │   12:34:56       █
█      Artist  ⏮ ⏯ ⏭     │   Aug  7         █   Now Playing (left) + clock & calendar (right)
█                        │   S M T W T F S  █
 ▀██████████████████████████████████████████▀
```

## Requirements

- An Apple Silicon MacBook **with a hardware notch** (e.g. MacBook Air M2). On Macs without
  a notch the panel opens from the top-center of the main display.
- macOS 15.0 or later. Built against the macOS 27 SDK.
- Xcode 27 (or its command-line tools, for the build script).

## Build the app

```sh
./scripts/build-app.sh --install
```

This runs `swift build -c release`, assembles `build/AgoyNotch.app` (binary +
`Resources/Info.plist` + `AppIcon.icns`), ad-hoc signs it, copies it to `/Applications` (replacing any old
copy, quitting a running one first) and opens it. Options:

- no flag — only build `build/AgoyNotch.app`
- `--universal` — build for both arm64 and x86_64
- `--help` — usage

After that, open **AgoyNotch** from Launchpad, Spotlight or `/Applications` like any app.
It has no Dock icon while idle; it lives in the menu bar.

## Opening Settings

The Settings window opens:

- when AgoyNotch starts (turn this off with *Show this window when AgoyNotch starts*),
- whenever you open AgoyNotch again while it is already running (Finder / Spotlight /
  Launchpad / `open -a AgoyNotch`),
- from the **menu-bar icon → Settings…**,
- with **⌘,** while the Settings window is focused.

While Settings is open AgoyNotch shows a Dock icon and an app menu; closing the window
returns it to menu-bar-only. Quit from the **menu-bar icon → Quit AgoyNotch**.

## Settings

Every change is saved (local `UserDefaults`) and applied **immediately** — no restart.

| Setting | Range (default) | What it does |
|---|---|---|
| Hover area → Width | 80–400 pt (your notch width) | Width of the invisible zone that opens the panel, centred on the notch. Applied live while dragging; the zone is outlined on screen for a moment so you can see it. |
| Hover area → Height | 10–80 pt (your notch height) | Height of that zone, from the top of the screen. Applied live, with the same outline. |
| Match notch | — | Resets width/height to the detected notch size (shown above the button). |
| Hover area → Vertical offset | 0–40 pt (0) | Moves only the hover zone down. The panel always starts at the top of the screen. Any offset above 0 leaves the very top edge (that many points) inert. |
| Open delay | 0–2 s, step 0.05 (0) | How long the cursor must rest on the notch before it opens. 0 = instant. Leaving earlier cancels the open. |
| Close delay | 0–2 s, step 0.05 (0.35) | How long after the cursor leaves the panel before it closes. 0 = instant. Coming back earlier keeps it open. |
| Animation duration | 0–1 s (0.35) | Speed of the grow/shrink spring. 0 = no animation. |
| Horizontal offset | −60–60 pt (0) | Shifts the panel and hover zone left/right if they are off-center on your Mac. |
| Panel width / height | 480–800 pt (600) / 180–320 pt (240) | Size of the expanded panel (height includes the band over the notch). |
| Show this window when AgoyNotch starts | on | Turn off if you use launch at login and don't want the window at every login. |
| Launch at login | off | Registers AgoyNotch as a login item (`SMAppService`). Only works from the built `.app`; errors are shown inline. |
| Clock & Calendar → Clock / Seconds | white | Colour of the `HH:mm` part and of the `:ss` part of the live clock (separately). |
| Clock & Calendar → Date & month | white | Month label, big day number and week-strip numbers. |
| Clock & Calendar → Weekday letters | white 50 % | The letters above the week strip. |
| Clock & Calendar → Today highlight / Today number | white / black | The circle behind today's date and the number on it. |
| Reset colours | — | Restores only the six colours. A live preview sits at the top of the section. |
| Reset to defaults | — | Restores every value above, colours included (except launch at login). |

While collapsed only the hover zone reacts to the cursor; once open, the whole panel does,
so you can move down to the transport buttons without it closing. While collapsed the overlay
ignores the mouse entirely (clicks reach the menu bar); hover is detected from the cursor
position in screen coordinates (inclusive of the very top row of the screen), re-checked on
every mouse move and on a short poll, so a cursor resting inside the notch opens the panel
without having to wiggle it.

The Settings window can be resized, minimized and zoomed.

## Live clock & calendar

Beside the Now Playing section, the expanded panel shows a **live clock and a compact
calendar**, laid out as the right-hand column with a subtle divider between the two sections:

- **Live clock** — the time ticks every second (24-hour `HH:mm:ss`) while the panel is
  expanded. `HH:mm` and `:ss` have separately configurable colours (Settings → Clock & Calendar). It is driven by SwiftUI's `TimelineView(.periodic(from: .now, by: 1))`, so there
  is no manual `Timer` to leak or tear down and the updates pause automatically when the panel
  is collapsed.
- **Calendar** — a month label (e.g. `Aug`), a large current-day number, and a one-week strip
  of weekday letters with today highlighted, plus a tasteful **"Nothing for today"** line.

Everything is computed **locally** from `Date` / `Calendar.current` / `Locale.current` /
`DateFormatter` and follows your system locale and calendar. There is **no network**, **no
telemetry**, and **no Calendar-events (EventKit) integration** — the "Nothing for today" line
is a static placeholder, not a read of your real events.

## Now Playing & permissions

**Now Playing uses AppleScript to Apple Music** (`Music.app`). AgoyNotch polls Music's
`player state` and the current track's name / artist / album, and reads album art as raw
local image bytes via `data of artwork 1 of current track`. Apple Music works best; this is
the live data source on macOS 27.

- **Grant Automation permission on first run.** The first time AgoyNotch sends an AppleScript
  command to Music, macOS shows an **Automation** consent prompt — click **OK / Allow**. You
  can review or re-enable it later under **System Settings → Privacy & Security → Automation**.
  If you deny it, the panel honestly shows **"Nothing playing"** instead of crashing.
- **Use the built `.app`.** The Automation grant is attached to the bundle identifier
  `com.azhazhell.agoynotch`, and the prompt text comes from `NSAppleEventsUsageDescription`
  in `Resources/Info.plist`. Running the bare executable from Xcode works but the prompt can
  be flaky there. Because the build script signs ad-hoc, each rebuild changes the signature,
  so macOS will likely ask again after every `--install` — just allow it. If the prompt stops
  appearing and Now Playing stays empty, reset the grant with
  `tccutil reset AppleEvents com.azhazhell.agoynotch` and relaunch. If Music isn't running or access is
  denied (error `-1743`), AgoyNotch logs a short message and shows "Nothing playing".
- **Graceful behavior.** If Music is stopped, not running, or unauthorized, the panel shows
  "Nothing playing" — it never forces Music to launch just to query it.

### Why AppleScript (historical MediaRemote note)

Earlier builds read Now Playing through Apple's **private** `MediaRemote` framework
(`dlopen`/`dlsym`; see `MediaRemoteBridge.swift`, kept as dormant historical code). Since
**macOS 15.4** the system `mediaremoted` daemon verifies caller entitlements before handing
back Now Playing data, so on **macOS 27** an unentitled build receives **empty** info and the
panel always read "Nothing playing". AppleScript to a scriptable player still works, so it is
now the live source. `MediaRemoteBridge` remains in the tree only to document that path.

## Xcode dev flow

1. Open `Package.swift` in Xcode, select **My Mac**, press **Run** (⌘R).
2. Debug builds print one geometry line per placement, e.g.
   `[AgoyNotch] screen.maxY=832.0 window.maxY=832.0 notch=(185.0, 32.0) …` —
   `window.maxY` must equal `screen.maxY`. The same line shows the window `frame`,
   `isVisible` and the hover zone in screen coordinates (`hoverZoneOnScreen`).
3. Debug builds also log `mouseEntered` / `mouseExited`, `open` / `close`,
   `ensureVisible isVisible=… ignoresMouseEvents=…`, and — each time the result changes —
   `hover inside=true|false expanded=… zone=… mouse=…` from the screen-space evaluator.

In this flow the app runs as a bare executable, not a bundle: launch at login is disabled,
and settings are stored under the executable's defaults domain, separate from the bundled
app's `com.azhazhell.agoynotch`. Use `./scripts/build-app.sh --install` for everyday use.

## App icon

The skull icon is `Resources/AppIcon.png` (1024 × 1024, original artwork; editable source
`Resources/AppIcon.svg`, regenerate the PNG with `python3 scripts/make-icon.py`).
`build-app.sh` turns it into `AppIcon.icns` with `sips` + `iconutil` (it warns and continues
without an icon if either is missing), and after `--install` refreshes LaunchServices. If
Finder or the Dock still shows the old icon, run `killall Dock`.

## App Store & signing note

The build script signs ad-hoc, which is enough for personal use on your own Mac. The
dormant `MediaRemoteBridge` uses a **private Apple framework**, which is **not eligible for
the Mac App Store**; to distribute outside the store, sign with a Developer ID and notarize.

## Privacy

- **No network calls.** There is no `URLSession`, no sockets, nothing phones home.
- **No telemetry.** Nothing is logged off-device.
- **Fully local & transparent.** The only other app AgoyNotch talks to is Apple Music on
  your Mac (via AppleScript), using the open source in this repository.

## How to quit

Click the **AgoyNotch menu-bar icon → Quit AgoyNotch** (⌘Q while the menu is open), or
⌘Q while the Settings window is focused.

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
  Resources/Info.plist                bundle Info.plist used by the build script
  Resources/AppIcon.svg / .png        skull app icon (SVG source + rendered 1024 px PNG)
  scripts/build-app.sh                builds, signs and (optionally) installs AgoyNotch.app
  scripts/make-icon.py                renders AppIcon.png (Python 3 stdlib only)
  Sources/AgoyNotch/
    AgoyNotchApp.swift                @main; NSApplicationDelegateAdaptor → AppDelegate; ⌘, → Settings
    AppDelegate.swift                 object graph, status item (About / Settings… / Quit), reopen
    AppSettings.swift                 all user settings (@Published, UserDefaults, live)
    SettingsView.swift                SwiftUI Settings form
    SettingsWindowController.swift    Settings NSWindow; .regular while open, .accessory after
    NotchWindow.swift                 borderless non-activating NSPanel above the menu bar + hover tracking
    NotchWindowController.swift       notch measurement, placement, screen-space hover, click-through
    NotchViewModel.swift              expand/collapse state, open/close delays, derived sizes
    NotchView.swift                   SwiftUI black panel growing out of the notch (Now Playing + clock)
    ClockCalendarView.swift           right column: live ticking clock + compact calendar
    NowPlaying/
      NowPlayingInfo.swift            plain media data model
      AppleScriptNowPlaying.swift     LIVE source: AppleScript → Apple Music (status + transport)
      MediaRemoteBridge.swift         dormant historical private-MediaRemote dlopen/dlsym boundary
      NowPlayingManager.swift         observable Now Playing service (polls AppleScript) + transport
```
