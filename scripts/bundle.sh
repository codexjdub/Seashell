#!/bin/bash
# Build Seashell for Apple silicon and Intel and wrap it in one signed,
# universal .app bundle.
#
# Signs with SIGN_IDENTITY if set, else the maintainer's "codexjdub" certificate
# if it's in the keychain, else ad hoc. Keeping the same certificate across
# builds keeps macOS privacy grants (Documents access).
#
# Build output goes to ~/Library/Caches/Seashell, outside iCloud Drive: iCloud
# tags bundles in Documents with Finder info that codesign rejects, and would
# upload every build.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PRODUCT=Seashell
BUNDLE_ID=io.github.codexjdub.seashell
VERSION=0.1.4
# The oldest macOS it runs on; Package.swift says the same. macOS 26 is the last
# for Intel Macs.
MINIMUM_MACOS=26.0
# The commit count only goes up, so each build has a higher build number.
BUILD=$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)

if [[ -n ${SIGN_IDENTITY:-} ]]; then
    IDENTITY=$SIGN_IDENTITY
elif security find-identity -v -p codesigning | grep -q '"codexjdub"'; then
    IDENTITY=codexjdub
else
    IDENTITY=-
    echo "No \"codexjdub\" certificate in the keychain, so signing ad hoc (set SIGN_IDENTITY to use your own)" >&2
fi

OUT="$HOME/Library/Caches/Seashell"
SCRATCH="$OUT/.build-$PRODUCT"
APP="$OUT/$PRODUCT.app"

# Apple silicon natively (sharing the tests' build folder), Intel by triple; then one binary.
swift build -c release --package-path "$ROOT" --scratch-path "$SCRATCH"
ARM_BIN="$(swift build -c release --package-path "$ROOT" --scratch-path "$SCRATCH" --show-bin-path)/$PRODUCT"
INTEL=(--triple "x86_64-apple-macosx$MINIMUM_MACOS" --scratch-path "$SCRATCH-x86_64")
swift build -c release --package-path "$ROOT" "${INTEL[@]}"
INTEL_BIN="$(swift build -c release --package-path "$ROOT" "${INTEL[@]}" --show-bin-path)/$PRODUCT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP/Contents/MacOS/$PRODUCT"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/Seal.png" "$APP/Contents/Resources/Seal.png"
cp -R "$ROOT/Resources/EasterEgg" "$APP/Contents/Resources/EasterEgg"

# LSUIElement: a menu bar app, with no Dock icon. NSServices: "Stash in Seashell"
# (files, folders or text, e.g. from Finder's right-click menu) and "New Seashell
# Note" (text) in the Services menu; ServiceProvider.swift handles them.
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$PRODUCT</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$PRODUCT</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>$MINIMUM_MACOS</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 codexjdub</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDocumentsFolderUsageDescription</key><string>Seashell keeps your stashed files and notes in Documents/Seashell so iCloud can sync them.</string>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Stash in Seashell</string></dict>
            <key>NSMessage</key><string>stashInSeashell</string>
            <key>NSPortName</key><string>$PRODUCT</string>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
            <key>NSSendTypes</key><array><string>public.utf8-plain-text</string></array>
            <key>NSRequiredContext</key><dict/>
        </dict>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>New Seashell Note</string></dict>
            <key>NSMessage</key><string>newSeashellNote</string>
            <key>NSPortName</key><string>$PRODUCT</string>
            <key>NSSendTypes</key><array><string>public.utf8-plain-text</string></array>
            <key>NSRequiredContext</key><dict/>
        </dict>
    </array>
</dict>
</plist>
EOF

codesign --force --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "$APP"
