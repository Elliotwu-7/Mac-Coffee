#!/bin/zsh
set -euo pipefail

RESOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER_SRC="$RESOURCE_DIR/MacCoffeeHelper"
HELPER_DST="/Library/PrivilegedHelperTools/com.elliotwu.maccoffee.helper"
PLIST_DST="/Library/LaunchDaemons/com.elliotwu.maccoffee.helper.plist"
SOCKET_PATH="/var/run/com.elliotwu.maccoffee.helper.sock"

if [[ ! -f "$HELPER_SRC" ]]; then
  echo "missing helper binary" >&2
  exit 1
fi

install -d -m 755 -o root -g wheel /Library/PrivilegedHelperTools
install -m 755 -o root -g wheel "$HELPER_SRC" "$HELPER_DST"

cat > "$PLIST_DST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.elliotwu.maccoffee.helper</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Library/PrivilegedHelperTools/com.elliotwu.maccoffee.helper</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/com.elliotwu.maccoffee.helper.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/com.elliotwu.maccoffee.helper.log</string>
</dict>
</plist>
PLIST

chown root:wheel "$PLIST_DST"
chmod 644 "$PLIST_DST"

launchctl bootout system/com.elliotwu.maccoffee.helper >/dev/null 2>&1 || true
rm -f "$SOCKET_PATH"
launchctl bootstrap system "$PLIST_DST"
launchctl kickstart -k system/com.elliotwu.maccoffee.helper

for _ in {1..20}; do
  [[ -S "$SOCKET_PATH" ]] && exit 0
  sleep 0.2
done

echo "helper socket not ready" >&2
exit 1
