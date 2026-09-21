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

ICONSET="$ROOT/Resources/AppIcon.iconset"
ICON="$APP/Contents/Resources/AirCardMac.icns"
mkdir -p "$ICONSET"
swift "$ROOT/Scripts/render_icon_fallback.swift" "$ICONSET"
sips -z 512 512 "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 256 256 "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 256 256 "$ICONSET/icon_256x256@2x.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 128 128 "$ICONSET/icon_256x256@2x.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 128 128 "$ICONSET/icon_128x128@2x.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 64 64 "$ICONSET/icon_128x128@2x.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 32 32 "$ICONSET/icon_32x32@2x.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 32 32 "$ICONSET/icon_32x32@2x.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 16 16 "$ICONSET/icon_16x16@2x.png" --out "$ICONSET/icon_16x16.png" >/dev/null
iconutil --convert icns "$ICONSET" --output "$ICON"
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
