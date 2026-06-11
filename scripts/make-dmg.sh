#!/bin/bash
# Build a Release DMG: dist/MadMac-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate > /dev/null
xcodebuild -project MadMac.xcodeproj -scheme MadMac -configuration Release \
  -derivedDataPath build-release build 2>&1 | grep -E "error:|BUILD" || true

APP="build-release/Build/Products/Release/MadMac.app"
[ -d "$APP" ] || { echo "build failed"; exit 1; }

VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "1.0")
STAGE=$(mktemp -d)
mkdir -p dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="dist/MadMac-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "MadMac" -srcfolder "$STAGE" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGE"
echo "created $DMG"
