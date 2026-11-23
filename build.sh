#!/bin/sh
set -eu
cd "$(dirname "$0")"
BUILD_ROOT="${BUILD_ROOT:-${TMPDIR:-/tmp}/DisplayCorners-build}"
SWIFTPM_CACHE="${SWIFTPM_CACHE:-$BUILD_ROOT/cache}"
mkdir -p "$BUILD_ROOT" "$SWIFTPM_CACHE"
swift build -c release --scratch-path "$BUILD_ROOT/swiftpm" --cache-path "$SWIFTPM_CACHE"
APP="$BUILD_ROOT/Display Corners.app"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
cp "$BUILD_ROOT/swiftpm/release/DisplayCorners" "$APP/Contents/MacOS/DisplayCorners"
codesign --force --sign - "$APP"
printf '%s\n' "$APP"
