#!/bin/sh
set -eu

: "${OUTPUT_DIR:?Set OUTPUT_DIR to a build directory outside the source tree}"
SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP_DIR="$OUTPUT_DIR/Agent Corner Preview.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$OUTPUT_DIR/module-cache"
cp "$SOURCE_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SOURCE_DIR"/Resources/*.png "$APP_DIR/Contents/Resources/"
cp "$SOURCE_DIR/Resources/LOBE-ICONS-LICENSE.txt" "$APP_DIR/Contents/Resources/"
swiftc -parse-as-library -target "$(uname -m)-apple-macosx26.0" \
    -module-cache-path "$OUTPUT_DIR/module-cache" \
    "$SOURCE_DIR/CornerPreview.swift" -o "$APP_DIR/Contents/MacOS/CornerPreview"
printf 'Built %s\n' "$APP_DIR"
