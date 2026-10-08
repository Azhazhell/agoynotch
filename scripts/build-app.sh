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
# build copy is removed once it is installed.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="AgoyNotch"
BUNDLE_ID="com.azhazhell.agoynotch"
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Stamp a fresh build number so icon caches see a new app version.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 1.$(date +%s)" "$APP/Contents/Info.plist"

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

# --- Ad-hoc sign (needed for a stable identity: Automation permission, login item) -------
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
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
