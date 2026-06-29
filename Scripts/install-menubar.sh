#!/bin/bash
#
# Build, sign, and install GroundLoop.app into /Applications.
#
# After running this you can launch GroundLoop from Spotlight or
# /Applications. The FIRST time it touches the keychain you'll see the
# password prompt — click "Always Allow". As long as the app is signed
# with the stable "GroundLoop Code Signing" identity (see
# ./Scripts/create-signing-cert.sh), that "Always Allow" survives every
# future rebuild + reinstall and you'll never be prompted again.
#
# Override the identity (e.g. a Developer ID) by setting CODESIGN_IDENTITY.
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="GroundLoop.app"
DEST="/Applications/$APP_NAME"

# Make sure a stable signing identity exists before we build, so the
# resulting app is never ad-hoc signed (which is what breaks "Always Allow").
STABLE_CERT="GroundLoop Code Signing"
if [[ -z "${CODESIGN_IDENTITY:-}" ]] && \
   ! security find-certificate -c "$STABLE_CERT" \
        "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
    echo "==> No stable signing identity yet — creating one..."
    "$(dirname "$0")/create-signing-cert.sh"
fi

RESIGN_IDENTITY="${CODESIGN_IDENTITY:-$STABLE_CERT}"

"$(dirname "$0")/bundle-menubar.sh"

echo "==> Installing to $DEST..."

# Quit any running instance so we can replace the bundle cleanly.
RUNNING_PID="$(pgrep -f "$APP_NAME/Contents/MacOS/groundloop-menubar" || true)"
if [[ -n "$RUNNING_PID" ]]; then
    echo "    stopping running instance (pid $RUNNING_PID)"
    kill "$RUNNING_PID" || true
    sleep 1
fi

rm -rf "$DEST"
cp -R ".build/$APP_NAME" "$DEST"

# Re-sign in place: copying can strip extended attributes on some setups.
codesign --force --deep --options runtime \
    --sign "$RESIGN_IDENTITY" \
    "$DEST" >/dev/null 2>&1 || true

echo "==> Launching $APP_NAME..."
open "$DEST"

echo
echo "Installed: $DEST  (signed: $RESIGN_IDENTITY)"
echo "Tip: when the keychain prompt appears, click 'Always Allow' — with the"
echo "     stable signature this is the LAST time you'll need to."
