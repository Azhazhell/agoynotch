#!/usr/bin/env bash
#
# build-app.sh — build AgoyNotch.app from the Swift package.
#
# Usage: ./scripts/build-app.sh [--install] [--universal]
#   --install    copy the app to /Applications (replacing any old copy) and open it
#   --universal  build for arm64 + x86_64 (default: this Mac's architecture)
#
# Output: build/AgoyNotch.app (ad-hoc signed), with Contents/Resources/AppIcon.icns built
# from Resources/AppIcon.png via sips + iconutil (skipped with a warning if unavailable).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="AgoyNotch"
BUNDLE_ID="com.azhazhell.agoynotch"
APP="$ROOT/build/$APP_NAME.app"
INSTALLED_APP="/Applications/$APP_NAME.app"

usage() {
    sed -n '5,7p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Parse flags first, so a bad flag fails before any build work -----------------------
INSTALL=0
UNIVERSAL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --universal) UNIVERSAL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 1 ;;
    esac
done

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

# --- App icon (Resources/AppIcon.png → AppIcon.icns) ------------------------------------
build_icon() {
    local src="$ROOT/Resources/AppIcon.png"
    [[ -f "$src" ]] || return 1
    command -v sips >/dev/null 2>&1 || return 1
    command -v iconutil >/dev/null 2>&1 || return 1
    local tmp
    tmp="$(mktemp -d)"
    local iconset="$tmp/AppIcon.iconset"
    mkdir -p "$iconset"
    local s
    for s in 16 32 128 256 512; do
        sips -z "$s" "$s" "$src" --out "$iconset/icon_${s}x${s}.png" >/dev/null || { rm -rf "$tmp"; return 1; }
        sips -z "$((s * 2))" "$((s * 2))" "$src" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null || { rm -rf "$tmp"; return 1; }
    done
    iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
}
# Called in an `if` so a failure does not abort the script under `set -e`.
if build_icon; then
    echo "Icon: AppIcon.icns"
else
    echo "warning: app icon not built (Resources/AppIcon.png missing or sips/iconutil unavailable) — continuing without icon" >&2
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

    # Replace the installed copy and launch it.
    rm -rf "$INSTALLED_APP"
    ditto "$APP" "$INSTALLED_APP"
    # Nudge Finder / the Dock to pick up the new icon.
    touch "$INSTALLED_APP"
    LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
    if [[ -x "$LSREGISTER" ]]; then
        "$LSREGISTER" -f "$INSTALLED_APP" >/dev/null 2>&1 || true
    fi
    echo "Installed $INSTALLED_APP"
    open "$INSTALLED_APP"
fi
