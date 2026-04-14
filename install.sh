#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="/Applications/Mac Coffee.app"

zsh "$ROOT_DIR/build.sh"
pkill -f "/Applications/Mac Coffee.app/Contents/MacOS/MacCoffee" >/dev/null 2>&1 || true
rm -rf "$TARGET"
cp -R "$ROOT_DIR/Mac Coffee.app" "$TARGET"

echo "Installed: $TARGET"
