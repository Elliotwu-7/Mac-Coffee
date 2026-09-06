#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"

required=(
  MACCOFFEE_DMG_PATH
  MACCOFFEE_APPCAST_URL
  MACCOFFEE_SPARKLE_PRIVATE_KEY_FILE
)
for key in $required; do
  [[ -n "${(P)key:-}" ]] || {
    print -u2 "Missing required appcast setting: $key"
    exit 64
  }
done
[[ "$MACCOFFEE_APPCAST_URL" == https://* ]] || {
  print -u2 "MACCOFFEE_APPCAST_URL must use HTTPS."
  exit 65
}
[[ -f "$MACCOFFEE_DMG_PATH" ]] || {
  print -u2 "DMG not found: $MACCOFFEE_DMG_PATH"
  exit 66
}
[[ -f "$MACCOFFEE_SPARKLE_PRIVATE_KEY_FILE" ]] || {
  print -u2 "Sparkle private key file not found."
  exit 66
}

generate_appcast="${MACCOFFEE_GENERATE_APPCAST:-}"
if [[ -z "$generate_appcast" ]]; then
  generate_appcast=$(/usr/bin/find "$ROOT_DIR/build" -type f \
    -path '*/bin/generate_appcast' -perm -111 -print -quit)
fi
[[ -x "$generate_appcast" ]] || {
  print -u2 "Sparkle 2.9.4 generate_appcast tool was not resolved."
  exit 69
}

output_dir="${MACCOFFEE_APPCAST_OUTPUT_DIR:-${MACCOFFEE_DMG_PATH:h}}"
input_dir=$(/usr/bin/mktemp -d -t maccoffee-appcast)
cleanup() {
  /bin/rm -rf "$input_dir"
}
trap cleanup EXIT INT TERM
dmg_name="${MACCOFFEE_DMG_PATH:t}"
release_notes_name="${dmg_name:r}.md"
/bin/mkdir -p "$output_dir"
/usr/bin/ditto "$MACCOFFEE_DMG_PATH" "$input_dir/$dmg_name"

if [[ -n "${MACCOFFEE_RELEASE_NOTES_FILE:-}" ]]; then
  [[ -f "$MACCOFFEE_RELEASE_NOTES_FILE" ]] || {
    print -u2 "Release notes file not found: $MACCOFFEE_RELEASE_NOTES_FILE"
    exit 66
  }
  /usr/bin/ditto "$MACCOFFEE_RELEASE_NOTES_FILE" "$input_dir/$release_notes_name"
else
  print "Mac Coffee ${dmg_name#MacCoffee-}" | /usr/bin/sed 's/\.dmg$//' > "$input_dir/$release_notes_name"
  print "Native menu-bar wake control, timed sessions, and battery safety." >> "$input_dir/$release_notes_name"
fi

download_prefix="${MACCOFFEE_APPCAST_URL%/*}/"
"$generate_appcast" \
  --ed-key-file "$MACCOFFEE_SPARKLE_PRIVATE_KEY_FILE" \
  --download-url-prefix "$download_prefix" \
  --embed-release-notes \
  --maximum-deltas 0 \
  -o "$input_dir/appcast.xml" \
  "$input_dir"

/usr/bin/xmllint --noout "$input_dir/appcast.xml"
/usr/bin/grep -Fq "$download_prefix$dmg_name" "$input_dir/appcast.xml"
/usr/bin/grep -q 'sparkle:edSignature=' "$input_dir/appcast.xml"
/usr/bin/ditto "$input_dir/appcast.xml" "$output_dir/appcast.xml"

print "Generated signed Sparkle appcast: $output_dir/appcast.xml"
