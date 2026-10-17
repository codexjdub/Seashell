#!/bin/bash
# Build a SwiftPM executable and wrap it in a signed .app bundle.
#
# Usage: scripts/bundle.sh <package-dir> <product> <bundle-id> [--agent]
#   --agent   menu bar app: no Dock icon (LSUIElement)
#
# Signs with the "codexjdub" identity (override with SIGN_IDENTITY). Keeping the
# same identity across builds keeps macOS privacy grants (Documents access).
#
# Build output goes to ~/Library/Caches/Seashell, outside iCloud Drive: iCloud
# tags bundles in Documents with Finder info that codesign rejects, and would
# upload every build.
set -euo pipefail

if [[ $# -lt 3 ]]; then
    echo "usage: $0 <package-dir> <product> <bundle-id> [--agent]" >&2
    exit 64
fi

PKG=$1
PRODUCT=$2
BUNDLE_ID=$3
AGENT=false
[[ ${4:-} == --agent ]] && AGENT=true
IDENTITY=${SIGN_IDENTITY:-codexjdub}

OUT="$HOME/Library/Caches/Seashell"
SCRATCH="$OUT/.build-$PRODUCT"
APP="$OUT/$PRODUCT.app"

swift build -c release --package-path "$PKG" --scratch-path "$SCRATCH"
BIN="$(swift build -c release --package-path "$PKG" --scratch-path "$SCRATCH" --show-bin-path)/$PRODUCT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$PRODUCT"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$PRODUCT</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$PRODUCT</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <key>LSUIElement</key><$AGENT/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDocumentsFolderUsageDescription</key><string>Seashell keeps your stashed files and notes in Documents/Seashell so iCloud can sync them.</string>
</dict>
</plist>
EOF

codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "$APP"
