#!/usr/bin/env bash
#
# build-app.sh — build AgoyNotch.app from the Swift package.
#
# Usage: ./scripts/build-app.sh [--install] [--universal] [--face PHOTO]
#   --install     copy the app to /Applications (replacing any old copy) and open it
#   --universal   build for arm64 + x86_64 (default: this Mac's architecture)
#   --face PHOTO  make the app icon from PHOTO (background removed → black, on this Mac only)
#
# Output: build/AgoyNotch.app (ad-hoc signed), with Contents/Resources/AppIcon.icns built
# via sips + iconutil from Resources/AppIcon-custom.png (the face icon, written by --face;
# never committed) if it exists, else Resources/AppIcon.png (the skull). With --install the
# build copy is removed once it is installed. The Now Playing helper (vendored
# mediaremote-adapter, Vendor/) is built into Contents/Frameworks with clang; if that fails
# the app still builds and falls back to Apple Music only.
#
# Optional: AGOYNOTCH_SIGN_IDENTITY="<Keychain code-signing certificate name>" signs with a
# stable identity instead of ad-hoc, so the Accessibility (message badges) and Automation
# grants survive rebuilds; --install then does not reset the Accessibility grant.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="AgoyNotch"
BUNDLE_ID="com.azhazhell.agoynotch"
SIGN_IDENTITY="${AGOYNOTCH_SIGN_IDENTITY:-}"
APP="$ROOT/build/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"

usage() {
    sed -n '5,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Parse flags first, so a bad flag fails before any build work -----------------------
INSTALL=0
UNIVERSAL=0
FACE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --install) INSTALL=1 ;;
        --universal) UNIVERSAL=1 ;;
        --face|--icon-photo)   FACE="${2:-}"; [[ -n "$FACE" && "$FACE" != -* ]] || { echo "error: --face needs a photo path" >&2; usage >&2; exit 1; }; shift ;;
        --face=*|--icon-photo=*) FACE="${1#*=}"; [[ -n "$FACE" ]] || { echo "error: --face needs a photo path" >&2; usage >&2; exit 1; } ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- Optional face icon (before any build work, so a bad photo fails fast) ---------------
# Runs only on this Mac (Vision + Core Image); the photo is never uploaded or committed.
if [[ -n "$FACE" ]]; then
    [[ -f "$FACE" && -r "$FACE" ]] || { echo "error: photo not found: $FACE" >&2; exit 1; }
    xcrun swiftc -O -target "$(uname -m)-apple-macos15.0" -o "$TMP/make-face-icon" "$ROOT/scripts/make-face-icon.swift" \
        || { echo "error: could not compile scripts/make-face-icon.swift" >&2; exit 1; }
    "$TMP/make-face-icon" "$FACE" "$ROOT/Resources/AppIcon-custom.png" \
        || { echo "error: could not make the icon from $FACE" >&2; exit 1; }
fi

# --- Build the release binary ------------------------------------------------------------
BUILD_ARGS=(-c release)
if [[ "$UNIVERSAL" -eq 1 ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

# --- Assemble the bundle -----------------------------------------------------------------
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
FW="$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Stamp a fresh build number so icon caches see a new app version.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1.$(date +%s)" "$APP/Contents/Info.plist"

# --- Now Playing helper (vendored mediaremote-adapter → MediaRemoteAdapter.framework) -----
# Called in an `if`, which disables `set -e` inside the function, so every step ends in
# `|| return 1`. Non-fatal: on failure the caller removes every helper file, so the bundle
# has the complete helper or none of it (Settings then says "helper not bundled").
build_adapter() {
    local v="$ROOT/Vendor/mediaremote-adapter"
    local src
    local ADAPTER_SOURCES=()
    for src in env get globals keys now_playing repeat seek send shuffle speed stream test; do
        ADAPTER_SOURCES+=("$v/src/adapter/$src.m")
    done
    ADAPTER_SOURCES+=("$v/src/private/MediaRemote.m" "$v/src/utility/Debounce.m" "$v/src/utility/helpers.m")
    mkdir -p "$FW/Versions/A/Resources" || return 1
    # Always universal: /usr/bin/perl is universal (mirrors upstream). -w: third-party code.
    xcrun --sdk macosx clang -dynamiclib -fobjc-arc -fvisibility=default -O2 -w \
        -arch arm64 -arch x86_64 -mmacosx-version-min=15.0 \
        -I "$v/include" -I "$v/src" \
        -framework Foundation -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers \
        -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
        -o "$FW/Versions/A/MediaRemoteAdapter" "${ADAPTER_SOURCES[@]}" || return 1
    cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST' || return 1
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.vandenbe.MediaRemoteAdapter</string>
    <key>CFBundleExecutable</key>
    <string>MediaRemoteAdapter</string>
    <key>CFBundleName</key>
    <string>MediaRemoteAdapter</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>0.1.0</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
</dict>
</plist>
PLIST
    ln -sfn A "$FW/Versions/Current" || return 1
    ln -sfn Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter" || return 1
    ln -sfn Versions/Current/Resources "$FW/Resources" || return 1
    codesign --force --sign - "$FW" || return 1
    cp "$v/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/mediaremote-adapter.pl" || return 1
    cp "$v/LICENSE" "$APP/Contents/Resources/MediaRemoteAdapter-LICENSE.txt" || return 1
}
if build_adapter; then
    echo "Now Playing helper: built"
else
    rm -rf "$FW" "$APP/Contents/Resources/mediaremote-adapter.pl" "$APP/Contents/Resources/MediaRemoteAdapter-LICENSE.txt"
    echo "warning: Now Playing helper (mediaremote-adapter) could not be built." >&2
    echo "warning: AgoyNotch will only show Apple Music; Settings will say \"helper not bundled\"." >&2
    echo "warning: See the clang output above; the icon and message badges are unaffected." >&2
fi

# --- App icon (face icon if present, else the skull → AppIcon.icns) ----------------------
ICON_SRC="$ROOT/Resources/AppIcon.png"
if [[ -f "$ROOT/Resources/AppIcon-custom.png" ]]; then
    ICON_SRC="$ROOT/Resources/AppIcon-custom.png"
fi
# Called in an `if`, which disables `set -e` inside the function, so every step ends in
# `|| return 1`.
build_icon() {
    local src="$1"
    [[ -f "$src" ]] || return 1
    command -v sips >/dev/null 2>&1 || return 1
    command -v iconutil >/dev/null 2>&1 || return 1
    local iconset="$TMP/AppIcon.iconset"
    rm -rf "$iconset" || return 1
    mkdir -p "$iconset" || return 1
    local s
    for s in 16 32 128 256 512; do
        sips -z "$s" "$s" "$src" --out "$iconset/icon_${s}x${s}.png" >/dev/null || return 1
        sips -z "$((s * 2))" "$((s * 2))" "$src" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null || return 1
    done
    iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns" || return 1
}
if build_icon "$ICON_SRC"; then
    echo "Icon: AppIcon.icns (from ${ICON_SRC#"$ROOT"/})"
else
    echo "error: app icon could not be built (${ICON_SRC#"$ROOT"/} missing, or sips/iconutil failed)" >&2
    exit 1
fi

# --- Sign (ad-hoc by default; AGOYNOTCH_SIGN_IDENTITY for a stable identity) -------------
if [[ -n "$SIGN_IDENTITY" ]]; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" \
        || { echo "error: could not sign with AGOYNOTCH_SIGN_IDENTITY=\"$SIGN_IDENTITY\" (see README → Stable signing)" >&2; exit 1; }
    echo "Signed with: $SIGN_IDENTITY"
else
    codesign --force --deep --sign - "$APP"
fi
codesign --verify --verbose "$APP"

# Helper self-test (only when it was built). `get` has an internal 2 s timeout. Non-fatal.
if [[ -d "$FW" ]]; then
    /usr/bin/perl "$APP/Contents/Resources/mediaremote-adapter.pl" "$FW" get --no-artwork >/dev/null 2>&1 \
        || echo "warning: Now Playing helper failed its self-test (Settings will show the reason)" >&2
fi
touch "$APP"
echo "Built $APP"

# --- Optional install --------------------------------------------------------------------
if [[ "$INSTALL" -eq 1 ]]; then
    # Quit any running copy so the old binary is not in use.
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
        sleep 1
        pkill -x "$APP_NAME" || true
    fi
    # A force-quit copy skips applicationWillTerminate; stop its orphaned Now Playing helper.
    pkill -f "$INSTALLED_APP/Contents/Resources/mediaremote-adapter.pl" >/dev/null 2>&1 || true
    # An ad-hoc signature changes on every build, which leaves a stale Accessibility grant
    # (shown "on" but no longer working). Reset it so the next launch with message badges on
    # prompts cleanly. A stable signing identity keeps the grant valid, so skip the reset.
    if [[ -z "$SIGN_IDENTITY" ]]; then
        tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi

    # Replace the installed copy and launch it.
    rm -rf "$INSTALLED_APP"
    ditto "$APP" "$INSTALLED_APP"
    # Nudge Finder / the Dock to pick up the new icon.
    touch "$INSTALLED_APP"
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    if [[ -x "$LSREGISTER" ]]; then
        "$LSREGISTER" -f "$INSTALLED_APP" >/dev/null 2>&1 || true
        # One bundle per bundle ID: drop the build copy so LaunchServices cannot pick it.
        "$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
    fi
    rm -rf "$APP"
    echo "Installed $INSTALLED_APP (build copy removed)"
    open "$INSTALLED_APP"
fi
