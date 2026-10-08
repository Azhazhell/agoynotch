# AgoyNotch

Turn your MacBook's hardware camera notch into a Dynamic Island–style interactive surface.

When idle AgoyNotch draws **nothing** (unless music is playing) — you see only your real notch. Move the cursor onto
the notch and a black panel grows out of it with a spring animation: one continuous black
shape whose top edge is the very top of the screen (it covers the notch and the menu-bar
strip beside it), with the content laid out just below the camera cutout. The panel shows
Now Playing from any app — Apple Music, Spotify, Apple TV, YouTube / SoundCloud in a browser
(album art, title, album, artist, the app's icon, prev / play-pause / next) and,
beside it, a **live clock (ticking every second) and a compact calendar**. Move away and it
shrinks back into the notch. It is a native macOS app written in Swift (AppKit + SwiftUI),
with no Swift package dependencies (one small vendored, BSD-licensed helper — see
[Now Playing & permissions](#now-playing--permissions)).

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
`Resources/Info.plist` + `AppIcon.icns` + the Now Playing helper, built with `clang` from
`Vendor/mediaremote-adapter`), ad-hoc signs it, copies it to `/Applications` (replacing any old
copy, quitting a running one first), resets AgoyNotch's Accessibility grant (see
[Message badges](#message-badges)), removes the `build/AgoyNotch.app` copy once it is
installed, and opens it. Options:

- no flag — only build `build/AgoyNotch.app`
- `--universal` — build for both arm64 and x86_64
- `--face PHOTO` — make the app icon from a photo of you (see [App icon](#app-icon))
- `--help` — usage

**Update** to the latest code: `git pull && ./scripts/build-app.sh --install`.

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
| Hover area → Height | 10–80 pt (your notch height) | Height of that zone, from the very top of the screen (the top edge is always included). Applied live, with the same outline. |
| Match notch | — | Resets width/height to the detected notch size (shown above the button). |
| Hover area → Show hover zone | off | Keeps the hover zone outlined on screen while the panel is closed. Parts that overlap the physical notch are hidden behind it. |
| Music activity → Show music activity beside the notch | on | While any Now Playing app plays and the panel is closed, shows the black pill beside the notch (see below). |
| Music activity → Equalizer colour | white | Colour of the pill's equalizer bars. |
| Music activity → Now Playing source | — | Read-only line: *all apps* when the helper runs, otherwise *Apple Music only* and why. |
| Notifications → Show message badges in the open panel | off | Shows the Messages / WhatsApp icon with its unread count in the open panel (see [Message badges](#message-badges)). |
| Notifications → Messages (iMessage) / WhatsApp | on / on | Per-app switches, used while the master toggle is on. |
| Notifications → Red dot beside the notch while closed | off | A small red dot right of the notch while the panel is closed and any badge is showing. |
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
| Reset to defaults | — | Restores every value above, colours, Show hover zone, the music activity and the notification settings included (except launch at login). |

While collapsed only the hover zone reacts to the cursor; once open, the whole panel does,
so you can move down to the transport buttons without it closing. The hover zone **always
includes the very top edge of the screen** and reaches down by Height; no setting can move
it away from the top. While the music activity pill is visible, the pill's area counts as
hover too, so hovering the artwork or equalizer opens the panel (trade-off: while music
plays, menu-bar items under the pill's wings open it as well; a zone wider than the notch
does the same). While collapsed the overlay ignores the mouse entirely (clicks reach the
menu bar); hover is detected from the cursor position in screen coordinates, re-checked on
every mouse move and on a short poll, so a cursor resting inside the notch opens the panel
after the open delay without having to wiggle it. A hover *vertical offset* stored by older
builds is discarded on launch.

The Settings window can be resized, minimized and zoomed.

## Music activity (collapsed)

While the panel is closed and **something is playing** (any Now Playing app), AgoyNotch shows a compact black
pill fused with the hardware notch: exactly the notch's height, flush with the top of the
screen, with a wing on each side. The left wing shows the album artwork (or, without
artwork, the playing app's icon; an SF Symbol `music.note` tile when that is unknown);
the right wing shows four animated equalizer bars (Settings → Equalizer colour). The bars
only animate while the pill is visible. Paused or nothing playing: nothing is drawn, as
before. Opening the panel grows it out of the pill. Turn it off with *Show music activity
beside the notch*.

## Message badges

Settings → **Notifications** → *Show message badges in the open panel* (off by default). While
the panel is open, the Messages (iMessage) and WhatsApp icons appear in the black band left of
the camera with their unread count — only the logo and the number, and only for apps with
unread messages. Counts above 99 show as `99+`.

**Click to open:** in the open panel, clicking a badge opens Messages / WhatsApp, and clicking
the Now Playing artwork or title brings the playing app (Music, Spotify, Safari/Chrome, TV…)
to the front; the panel then closes.

- **Where the number comes from:** the app's red **Dock badge**, read through the
  Accessibility API every 3 s (and when the panel opens). The app must be running (in the
  background is fine), and *System Settings → Notifications → Messages / WhatsApp → Badge
  application icon* must be on. Message text and senders are never read.
- **Accessibility access:** turning the feature on shows the macOS prompt once; Settings shows
  *Accessibility access needed* with a **Grant access…** button until it is allowed (System
  Settings → Privacy & Security → Accessibility). While the feature is off, AgoyNotch never
  asks and never reads the Dock.
- **After every `--install`** the build is signed ad-hoc (a new signature), so the script
  resets the grant and macOS asks again. To keep it, use [stable signing](#stable-signing-optional).

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

**All apps (default).** AgoyNotch runs the vendored
[ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (BSD-3, commit
`e3ff502`, in `Vendor/`) as a child process: `/usr/bin/perl mediaremote-adapter.pl
MediaRemoteAdapter.framework stream`. Since macOS 15.4 apps can no longer read the system
Now Playing state directly; the Apple-signed `perl` still can, and streams it to AgoyNotch as
JSON lines. That covers Apple Music, Spotify, Apple TV and browser players (YouTube,
SoundCloud, Spotify Web…). The panel shows the title, artist, artwork and the playing app's
icon, and prev / play-pause / next go to that app. Nothing leaves your Mac. The helper is
stopped when AgoyNotch quits; if it crashes it is restarted (at most 3 times a minute).

**Apple Music fallback.** AgoyNotch also polls Apple Music with AppleScript. When the helper
is missing (`swift run` / Xcode dev flow, or its build failed — `build-app.sh` then prints a
`warning:`) or fails, Apple Music still works, and Settings → Music activity shows
"Now Playing source: Apple Music only — <reason>". When both have media, whatever is playing
wins.

- **Automation permission** is needed only for that Apple Music fallback. The first
  AppleScript call to Music shows an **Automation** prompt — click **OK / Allow** (review it
  under **System Settings → Privacy & Security → Automation**). Because the build is signed
  ad-hoc, macOS may ask again after each `--install`. If it stops asking and Apple Music
  stays empty, run `tccutil reset AppleEvents com.azhazhell.agoynotch` and relaunch.
- **Graceful behavior.** Nothing playing, Music not running or access denied → the panel
  shows "Nothing playing"; AgoyNotch never launches Music just to query it.

### Troubleshooting

- Check the Settings line *Now Playing source*.
- `pgrep -f mediaremote-adapter` shows the running helper (and nothing after Quit).
- `killall Dock` if Finder or the Dock shows a stale icon.
- No message badge: check that the Dock itself shows the red count; it only does when
  *System Settings → Notifications → Messages / WhatsApp → Badge application icon* is on,
  because AgoyNotch only reads the Dock badge.
- Badges stay empty although access looks granted: `tccutil reset Accessibility
  com.azhazhell.agoynotch`, relaunch AgoyNotch and allow it again.

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

**Your face as the icon.** On your Mac:

```sh
./scripts/build-app.sh --face ~/Downloads/<photo>.jpg --install
```

`scripts/make-face-icon.swift` (compiled by the build script, Apple frameworks only) finds the
person with Vision, replaces the background with black, crops a square around the face and
writes the same rounded square as the skull to `Resources/AppIcon-custom.png`. Everything runs
locally — the photo is never uploaded, and `AppIcon-custom.png` is gitignored so it is never
committed. Later builds without `--face` keep using it. The build stops with an `error:` line
if the photo is missing, smaller than 256 px on the short side, or has no person in it.
(`--icon-photo PHOTO` is accepted as an alias.)

**Back to the skull:** delete `Resources/AppIcon-custom.png` and run
`./scripts/build-app.sh --install` again. The skull is `Resources/AppIcon.png` (1024 × 1024,
original artwork; editable source `Resources/AppIcon.svg`, regenerate the PNG with
`python3 scripts/make-icon.py`).

`build-app.sh` turns the icon into `AppIcon.icns` with `sips` + `iconutil` (the build fails if
that does not work), stamps a new `CFBundleVersion`, and on `--install` re-registers the
installed copy with LaunchServices and removes the build copy, so macOS only knows one
AgoyNotch. The app also sets its Dock icon itself at launch and whenever Settings opens. If
Finder or the Dock still shows an old icon, run `killall Dock`.

## App Store & signing note

The build script signs ad-hoc, which is enough for personal use on your own Mac. The
Now Playing helper uses Apple's **private** MediaRemote framework, which is **not eligible
for the Mac App Store**; to distribute outside the store, sign with a Developer ID and notarize.

### Stable signing (optional)

An ad-hoc signature changes on every build, so macOS forgets the Accessibility and Automation
grants after each `--install`. To keep them, sign with your own certificate:

1. **Keychain Access → Certificate Assistant → Create a Certificate…**: name it e.g.
   `AgoyNotch Local`, Identity Type *Self Signed Root*, Certificate Type **Code Signing**.
2. Build with it:
   ```sh
   AGOYNOTCH_SIGN_IDENTITY="AgoyNotch Local" ./scripts/build-app.sh --install
   ```
   With an identity set, `--install` does not reset the Accessibility grant.
3. The first time (switching from ad-hoc), reset the old grants once and allow them again:
   `tccutil reset Accessibility com.azhazhell.agoynotch` and
   `tccutil reset AppleEvents com.azhazhell.agoynotch`.

## Privacy

- **No network calls.** There is no `URLSession`, no sockets, nothing phones home.
- **No telemetry.** Nothing is logged off-device.
- **Fully local & transparent.** AgoyNotch reads the system Now Playing state through the
  local helper and talks to Apple Music on your Mac via AppleScript, using the open source in
  this repository.
- **Message badges** (off by default) read only the unread **count** from the Dock badge —
  never message text, senders or chat databases.

## Third-party

- [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) by Jonas van den
  Berg, BSD-3-Clause, vendored unmodified in `Vendor/mediaremote-adapter` (see its
  `UPSTREAM.md`). Its licence ships in the app as
  `Contents/Resources/MediaRemoteAdapter-LICENSE.txt`.

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
  scripts/make-face-icon.swift        photo → face app icon (Vision; run by build-app.sh --face)
  Vendor/mediaremote-adapter/         vendored Now Playing helper (BSD-3; UPSTREAM.md)
  Sources/AgoyNotch/
    AgoyNotchApp.swift                @main; NSApplicationDelegateAdaptor → AppDelegate; ⌘, → Settings
    AppDelegate.swift                 object graph, status item (About / Settings… / Quit), reopen
    BundledAppIcon.swift              applies the bundled AppIcon.icns as the Dock / About icon
    AppSettings.swift                 all user settings (@Published, UserDefaults, live)
    SettingsView.swift                SwiftUI Settings form
    SettingsWindowController.swift    Settings NSWindow; .regular while open, .accessory after
    NotchWindow.swift                 borderless non-activating NSPanel above the menu bar + hover tracking
    NotchWindowController.swift       notch measurement, placement, screen-space hover, click-through
    NotchViewModel.swift              expand/collapse state, open/close delays, derived sizes
    NotchView.swift                   SwiftUI black panel growing out of the notch (Now Playing + clock)
    MusicActivityView.swift           collapsed music pill: artwork wing + animated equalizer
    ClockCalendarView.swift           right column: live ticking clock + compact calendar
    AppIconViews.swift                the playing app's icon (panel + pill)
    Notifications/
      MessageBadge.swift              badge model + label normalisation (pure)
      DockBadgeReader.swift           reads Dock badge text via Accessibility (background queue)
      MessageBadgeMonitor.swift       polls while enabled, Accessibility prompt/status
      MessageBadgesView.swift         panel badge row (logo + count) and the collapsed dot
    NowPlaying/
      NowPlayingInfo.swift            plain media data model
      AdapterStream.swift             helper JSON lines → snapshot, source precedence (pure)
      MediaRemoteAdapterClient.swift  runs the helper child process, restarts, commands
      AppleScriptNowPlaying.swift     Apple Music fallback: AppleScript (status + transport)
      NowPlayingManager.swift         observable Now Playing service (helper + AppleScript) + transport
```
