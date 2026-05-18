#!/bin/bash
#
# Build, sign, and install GroundLoop.app into /Applications.
#
# After running this you can launch GroundLoop from Spotlight or
# /Applications. The first time it touches the keychain you'll see the
# password prompt — click "Always Allow" and it will stick until the
# next time you rebuild + reinstall (because ad-hoc signatures change
# every build).
#
# To make "Always Allow" survive rebuilds, set CODESIGN_IDENTITY to a
# stable code-signing certificate (self-signed or Developer ID).
#
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="GroundLoop.app"
DEST="/Applications/$APP_NAME"

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
    --sign "${CODESIGN_IDENTITY:--}" \
    "$DEST" >/dev/null 2>&1 || true

echo "==> Launching $APP_NAME..."
open "$DEST"

echo
echo "Installed: $DEST"
echo "Tip: when the keychain prompt appears, click 'Always Allow' once."
