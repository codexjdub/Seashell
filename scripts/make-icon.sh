#!/bin/bash
# Rebuild Resources/AppIcon.icns from Resources/AppIcon.svg.
#
# Usage: scripts/make-icon.sh
#
# Renders every size macOS asks for (16 to 1024 px) and packs them with
# iconutil. bundle.sh copies the result into the app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

xcrun swiftc -O -o "$WORK/svg2png" "$ROOT/scripts/svg2png.swift"
mkdir "$WORK/AppIcon.iconset"
for spec in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x \
            256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    "$WORK/svg2png" "$ROOT/Resources/AppIcon.svg" "$WORK/AppIcon.iconset/icon_${spec#*:}.png" "${spec%%:*}"
done
iconutil -c icns "$WORK/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
echo "$ROOT/Resources/AppIcon.icns"
