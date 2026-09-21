#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build_app.sh"

APP="$ROOT/build/AirCardMac.app"
DMG="$ROOT/build/AirCardMac.dmg"
STAGING="$(mktemp -d -t aircard-dmg.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT

ditto --norsrc --noextattr --noqtn "$APP" "$STAGING/AirCardMac.app"
xattr -cr "$STAGING/AirCardMac.app" 2>/dev/null || true
for attribute in com.apple.FinderInfo com.apple.ResourceFork com.apple.fileprovider.fpfs#P; do
  xattr -dr "$attribute" "$STAGING/AirCardMac.app" 2>/dev/null || true
done
codesign --verify --deep --strict "$STAGING/AirCardMac.app"

hdiutil create \
  -volname "AirCard macOS" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$DMG"

rm -rf "$STAGING"
trap - EXIT
xattr -cr "$APP" 2>/dev/null || true
codesign --verify --deep --strict "$APP"
echo "DMG listo: $DMG"
