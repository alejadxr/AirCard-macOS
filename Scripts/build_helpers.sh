#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_DIR="$ROOT/Sources/Native"
OUT_DIR="$ROOT/Resources/bin"

if [[ ! -f "$SOURCE_DIR/device_helper.m" || ! -f "$SOURCE_DIR/airtraffic_host.m" ]]; then
  echo "No encuentro los fuentes nativos vendorizados en $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
CLANG="$(xcrun --find clang)"
SDK_FLAGS=(-isysroot "$(xcrun --sdk macosx --show-sdk-path)" -framework Foundation -framework CoreFoundation)
ARCH_FLAGS=(-arch arm64 -arch x86_64)

"$CLANG" -fobjc-arc -O2 -Wall -Wextra "${ARCH_FLAGS[@]}" \
  "${SDK_FLAGS[@]}" \
  /System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice \
  "$SOURCE_DIR/device_helper.m" -o "$OUT_DIR/device_helper"

"$CLANG" -fobjc-arc -O2 -Wall -Wextra "${ARCH_FLAGS[@]}" \
  "${SDK_FLAGS[@]}" \
  /System/Library/PrivateFrameworks/AirTrafficHost.framework/AirTrafficHost \
  "$SOURCE_DIR/airtraffic_host.m" -o "$OUT_DIR/airtraffic_host"

codesign --force --sign - "$OUT_DIR/device_helper" "$OUT_DIR/airtraffic_host"
echo "Helpers creados en $OUT_DIR"
