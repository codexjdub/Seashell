#!/bin/bash
# Build Seashell, install it to /Applications and (re)start it.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUNDLE_ID=io.github.codexjdub.seashell
BUILT="$HOME/Library/Caches/Seashell/Seashell.app"
INSTALLED="/Applications/Seashell.app"

# Quit the running copy, if any, and wait for it to exit.
osascript -e "if application id \"$BUNDLE_ID\" is running then tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
for _ in {1..50}; do
    pgrep -f "Seashell.app/Contents/MacOS/Seashell" >/dev/null || break
    sleep 0.1
done

"$ROOT/scripts/bundle.sh" "$ROOT" Seashell "$BUNDLE_ID" --agent

rm -rf "$INSTALLED"
ditto "$BUILT" "$INSTALLED"
codesign --verify --strict "$INSTALLED"
open "$INSTALLED"
echo "Installed and opened $INSTALLED"
