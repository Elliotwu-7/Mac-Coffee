#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

variant="${1:-direct}"
case "$variant" in
  direct)
    scheme="MacCoffeeDirect"
    build_dir="$ROOT_DIR/build/local-direct"
    destination_dir="$ROOT_DIR/dist/local"
    ;;
  app-store)
    scheme="MacCoffeeAppStore"
    build_dir="$ROOT_DIR/build/local-app-store"
    destination_dir="$ROOT_DIR/dist/local-app-store"
    ;;
  *)
    print -u2 "Usage: $0 [direct|app-store]"
    exit 64
    ;;
esac

command -v xcodegen >/dev/null || {
  print -u2 "XcodeGen 2.46.0 or later is required. Run: brew bundle"
  exit 69
}

cd "$ROOT_DIR"
xcodegen generate

optional_build_settings=()
if [[ "$variant" == direct && -n "${MACCOFFEE_SPARKLE_PUBLIC_KEY:-}" ]]; then
  optional_build_settings+=(MACCOFFEE_SPARKLE_PUBLIC_KEY="$MACCOFFEE_SPARKLE_PUBLIC_KEY")
fi

xcodebuild build \
  -project MacCoffee.xcodeproj \
  -scheme "$scheme" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  ENABLE_HARDENED_RUNTIME=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  DEVELOPMENT_TEAM= \
  "${optional_build_settings[@]}"

source_app="$build_dir/Build/Products/Release/Mac Coffee.app"
destination_app="$destination_dir/Mac Coffee.app"
[[ -d "$source_app" ]] || {
  print -u2 "Build completed without the expected app: $source_app"
  exit 66
}

/bin/mkdir -p "$destination_dir"
/bin/rm -rf "$destination_app"
/usr/bin/ditto "$source_app" "$destination_app"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$destination_app"
/usr/bin/lipo "$destination_app/Contents/MacOS/Mac Coffee" -verify_arch arm64 x86_64

print "Built and verified: $destination_app"
