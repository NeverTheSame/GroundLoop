#!/bin/bash
#
# Build a signed GroundLoop.app bundle.
#
# Usage:
#   ./Scripts/bundle-menubar.sh                       # ad-hoc sign (free)
#   CODESIGN_IDENTITY="Developer ID Application: ..." \
#     ./Scripts/bundle-menubar.sh                     # Developer ID sign
#
# A stable code signature is required so macOS Keychain ACLs survive
# launches: an unsigned (or freshly-rebuilt ad-hoc) binary has a new
# code-directory hash every time, which is why the keychain password
# prompt keeps reappearing in `swift run`.
#
set -euo pipefail

cd "$(dirname "$0")/.."

PRODUCT="groundloop-menubar"
APP_NAME="GroundLoop.app"
BUILD_DIR=".build"
APP_DIR="$BUILD_DIR/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "==> Building $PRODUCT (release)..."
swift build -c release --product "$PRODUCT"

BIN_PATH="$BUILD_DIR/release/$PRODUCT"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Assembling $APP_NAME..."
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH" "$CONTENTS/MacOS/$PRODUCT"
cp "Sources/groundloop-menubar/Resources/Info.plist" "$CONTENTS/Info.plist"

# Copy the ServiceLogos bundle that SwiftPM produced next to the binary.
LOGO_BUNDLE=".build/release/GroundLoop_groundloop-menubar.bundle"
if [[ -d "$LOGO_BUNDLE" ]]; then
    cp -R "$LOGO_BUNDLE" "$CONTENTS/Resources/"
fi

echo "==> Code-signing with identity: $IDENTITY"
codesign --force --deep --options runtime \
    --sign "$IDENTITY" \
    "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR" || true

echo
echo "Built: $APP_DIR"
echo "Run:   open $APP_DIR"
echo "Install (recommended for stable keychain identity):"
echo "       ./Scripts/install-menubar.sh"

