#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

cd "$ROOT_DIR"
xcodegen generate

derived_data="$ROOT_DIR/build/screenshots"
xcodebuild build \
  -project MacCoffee.xcodeproj \
  -scheme MacCoffeeScreenshots \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO

generator="$derived_data/Build/Products/Release/MacCoffeeScreenshots.app/Contents/MacOS/MacCoffeeScreenshots"
[[ -x "$generator" ]] || {
  print -u2 "Screenshot generator was not built: $generator"
  exit 66
}

"$generator" "$ROOT_DIR"
"$ROOT_DIR/scripts/verify-release-assets.sh"
