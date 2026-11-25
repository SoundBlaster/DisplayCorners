#!/bin/sh
set -eu

: "${BUILD_ROOT:?Set BUILD_ROOT to an external build directory}"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SWIFTPM_CACHE=${SWIFTPM_CACHE:-"$BUILD_ROOT/cache"}
APP="$BUILD_ROOT/Display Corners Debug.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SWIFTPM_CACHE"
swift build --package-path "$ROOT" -c debug --scratch-path "$BUILD_ROOT/swiftpm" --cache-path "$SWIFTPM_CACHE"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.displaycorners.mockdebug' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Display Corners Debug' "$APP/Contents/Info.plist"
cp -R "$ROOT/Resources/." "$APP/Contents/Resources/"
cp "$ROOT/prototypes/corner-preview/Resources/codex.png" "$ROOT/prototypes/corner-preview/Resources/LOBE-ICONS-LICENSE.txt" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/CodexAdapter"
cp "$ROOT/prototypes/codex-adapter/adapter.py" "$ROOT/prototypes/codex-adapter/hook.py" "$ROOT/prototypes/codex-adapter/install.py" "$ROOT/prototypes/codex-adapter/paths.py" "$ROOT/prototypes/codex-adapter/title_lookup.py" "$APP/Contents/Resources/CodexAdapter/"
cp "$BUILD_ROOT/swiftpm/debug/DisplayCorners" "$APP/Contents/MacOS/DisplayCorners"
codesign --force --sign - "$APP"
if [ "$#" -gt 0 ]; then
    DISPLAY_CORNERS_MOCK_SOCKET="$1" "$APP/Contents/MacOS/DisplayCorners"
else
    "$APP/Contents/MacOS/DisplayCorners"
fi
