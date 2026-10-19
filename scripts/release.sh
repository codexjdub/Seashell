#!/bin/bash
# Build Seashell-<version>.zip, ready to attach to a GitHub release, and print
# its SHA-256.
#
# Refuses to run with uncommitted changes, so the zip matches a commit, and
# refuses an ad hoc signature: releases need a certificate (codexjdub, or
# SIGN_IDENTITY; see bundle.sh) so updates keep the same identity.
#
# Set NOTARY_PROFILE to a notarytool keychain profile to have Apple notarize the
# app and staple the ticket. That needs a Developer ID certificate.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$HOME/Library/Caches/Seashell/Seashell.app"
OUT="$HOME/Library/Caches/Seashell/release"

if [[ -n $(git -C "$ROOT" status --porcelain) ]]; then
    echo "Commit your changes first, so the release matches a commit." >&2
    exit 1
fi

"$ROOT/scripts/bundle.sh"

if codesign -dv "$APP" 2>&1 | grep -q "Signature=adhoc"; then
    echo "The app is signed ad hoc. Releases need a certificate: install codexjdub or set SIGN_IDENTITY." >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
ZIP="$OUT/Seashell-$VERSION.zip"
mkdir -p "$OUT"
rm -f "$ZIP"

if [[ -n ${NOTARY_PROFILE:-} ]]; then
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm "$ZIP"
fi

ditto -c -k --keepParent "$APP" "$ZIP"
echo
echo "$ZIP ($(git -C "$ROOT" rev-parse --short HEAD))"
shasum -a 256 "$ZIP"
