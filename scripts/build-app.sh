#!/usr/bin/env bash
#
# build-app.sh — build AgoyNotch.app from the Swift package.
#
# Usage: ./scripts/build-app.sh [--install] [--universal]
#   --install    copy the app to /Applications (replacing any old copy) and open it
#   --universal  build for arm64 + x86_64 (default: this Mac's architecture)
#
# Output: build/AgoyNotch.app (ad-hoc signed).
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

# --- Ad-hoc sign (needed for a stable identity: Automation permission, login item) -------
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
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
    echo "Installed $INSTALLED_APP"
    open "$INSTALLED_APP"
fi
