#!/bin/sh
set -eu
cd "$(dirname "$0")"
BUILD_ROOT="${BUILD_ROOT:-${TMPDIR:-/tmp}/DisplayCorners-build}"
SWIFTPM_CACHE="${SWIFTPM_CACHE:-$BUILD_ROOT/cache}"
mkdir -p "$BUILD_ROOT" "$SWIFTPM_CACHE"
if [ "${UNIVERSAL:-0}" = 1 ]; then
    set -- --arch arm64 --arch x86_64
else
    set --
fi
swift build -c release --scratch-path "$BUILD_ROOT/swiftpm" --cache-path "$SWIFTPM_CACHE" "$@"
BIN_DIR=$(swift build -c release --scratch-path "$BUILD_ROOT/swiftpm" --cache-path "$SWIFTPM_CACHE" "$@" --show-bin-path)
APP="$BUILD_ROOT/Display Corners.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/. "$APP/Contents/Resources/"
cp prototypes/corner-preview/Resources/codex.png prototypes/corner-preview/Resources/LOBE-ICONS-LICENSE.txt "$APP/Contents/Resources/"
cp "$BIN_DIR/DisplayCorners" "$APP/Contents/MacOS/DisplayCorners"
cp "$BIN_DIR/DisplayCornersHook" "$APP/Contents/Helpers/DisplayCornersHook"
codesign --force --sign - "$APP/Contents/Helpers/DisplayCornersHook"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
