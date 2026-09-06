#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
version="${MACCOFFEE_VERSION:-2.0.1}"
app_path="${MACCOFFEE_APP_PATH:-$ROOT_DIR/dist/local/Mac Coffee.app}"
dmg_path="${MACCOFFEE_DMG_PATH:-$ROOT_DIR/dist/local/MacCoffee-${version}.dmg}"

[[ -d "$app_path" ]] || {
  print -u2 "App not found: $app_path"
  print -u2 "Run scripts/build-local.sh direct first."
  exit 66
}

/usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"
/usr/bin/lipo "$app_path/Contents/MacOS/Mac Coffee" -verify_arch arm64 x86_64

staging_dir="$(/usr/bin/mktemp -d /tmp/maccoffee-dmg.XXXXXX)"
cleanup() {
  /bin/rm -rf "$staging_dir"
}
trap cleanup EXIT INT TERM

/usr/bin/ditto "$app_path" "$staging_dir/Mac Coffee.app"
/bin/ln -s /Applications "$staging_dir/Applications"
/bin/mkdir -p "${dmg_path:h}"
/bin/rm -f "$dmg_path"

/usr/bin/hdiutil create \
  -volname "Mac Coffee" \
  -srcfolder "$staging_dir" \
  -format UDZO \
  -ov \
  "$dmg_path" >/dev/null

if [[ -n "${MACCOFFEE_SIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --timestamp --sign "$MACCOFFEE_SIGN_IDENTITY" "$dmg_path"
else
  /usr/bin/codesign --force --sign - "$dmg_path"
fi
/usr/bin/codesign --verify --verbose=2 "$dmg_path"

print "Packaged and verified: $dmg_path"
