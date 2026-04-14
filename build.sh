#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MacCoffee"
HELPER_NAME="MacCoffeeHelper"
APP_BUNDLE="$ROOT_DIR/Mac Coffee.app"
EXECUTABLE_PATH="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
INFO_PLIST_PATH="$APP_BUNDLE/Contents/Info.plist"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
ICONSET_PATH="$ROOT_DIR/Resources/AppIcon.iconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$RESOURCES_DIR"

iconutil -c icns "$ICONSET_PATH" -o "$ICON_PATH"

swiftc \
  -parse-as-library \
  -target arm64-apple-macos13.0 \
  -sdk "$SDK_PATH" \
  -framework AppKit \
  -framework Foundation \
  -framework IOKit \
  -framework SwiftUI \
  "$ROOT_DIR/Sources/MacCoffeeApp.swift" \
  -o "$EXECUTABLE_PATH"

swiftc \
  -target arm64-apple-macos13.0 \
  -sdk "$SDK_PATH" \
  "$ROOT_DIR/Sources/MacCoffeeHelper.swift" \
  -o "$RESOURCES_DIR/$HELPER_NAME"

cp "$ROOT_DIR/Info.plist" "$INFO_PLIST_PATH"
cp "$ROOT_DIR/Resources/install_helper.sh" "$RESOURCES_DIR/install_helper.sh"

echo "Built: $APP_BUNDLE"
