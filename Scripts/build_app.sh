#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/build_helpers.sh"
swift build -c release --arch arm64
swift build -c release --arch x86_64

APP="$ROOT/build/AirCardMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/bin"

lipo -create \
  "$ROOT/.build/arm64-apple-macosx/release/AirCardMac" \
  "$ROOT/.build/x86_64-apple-macosx/release/AirCardMac" \
  -output "$APP/Contents/MacOS/AirCardMac"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/bin/device_helper" "$APP/Contents/Resources/bin/device_helper"
cp "$ROOT/Resources/bin/airtraffic_host" "$APP/Contents/Resources/bin/airtraffic_host"
chmod +x "$APP/Contents/MacOS/AirCardMac" "$APP/Contents/Resources/bin/"*
cp "$ROOT/Resources/Assets.car" "$APP/Contents/Resources/Assets.car"
cp "$ROOT/Resources/AirCardIcon.icns" "$APP/Contents/Resources/AirCardIcon.icns"
cp -R "$ROOT/Resources/AirCardIcon.icon" "$APP/Contents/Resources/AirCardIcon.icon"

# Finder/FileProvider can attach metadata to generated bundles in this
# workspace. Strip only the known code-signing-incompatible attributes before
# signing; do not remove anything from the user's wider filesystem.
xattr -cr "$APP" 2>/dev/null || true
for attribute in com.apple.FinderInfo com.apple.ResourceFork com.apple.fileprovider.fpfs#P; do
  xattr -d "$attribute" "$APP" 2>/dev/null || true
  xattr -dr "$attribute" "$APP" 2>/dev/null || true
done
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "App listo: $APP"
