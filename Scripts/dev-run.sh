#!/bin/bash
#
# Fast dev-loop runner for groundloop-menubar.
#
# `swift build` / `swift run` always produce a brand-new ad-hoc signature
# (fresh code hash, identifier "groundloop-menubar-<hash>") on every build.
# macOS Keychain ACLs are pinned to the code signature, so every dev rebuild
# looks like a "new app" and the "Claude Code-credentials" prompt returns —
# forever, in the normal dev loop. See ./Scripts/create-signing-cert.sh for
# the full explanation of why signature stability matters.
#
# This script closes that gap: it builds the binary, then re-signs the LOOSE
# executable in place with the exact same identity AND identifier as the
# installed /Applications/GroundLoop.app:
#     --sign "GroundLoop Code Signing" --identifier com.groundloop.menubar
# That produces a byte-identical Designated Requirement to the production
# app, so it inherits whatever "Always Allow" you already granted — with
# zero new prompts, no matter how many times you rebuild.
#
# Usage:
#   ./Scripts/dev-run.sh              # debug build (fast), sign, launch
#   ./Scripts/dev-run.sh --release    # release build, sign, launch
#   ./Scripts/dev-run.sh --no-run     # build + sign only, don't launch
#
# Override the identity (e.g. to test with a Developer ID) via
# CODESIGN_IDENTITY, same as the other Scripts/*.sh.
#
set -euo pipefail

cd "$(dirname "$0")/.."

PRODUCT="groundloop-menubar"
BUNDLE_ID="com.groundloop.menubar"
STABLE_CERT="GroundLoop Code Signing"
CONFIG="debug"
RUN_AFTER=1

for arg in "$@"; do
    case "$arg" in
        --release) CONFIG="release" ;;
        --no-run)  RUN_AFTER=0 ;;
        -h|--help)
            echo "usage: $0 [--release] [--no-run]"
            exit 0
            ;;
        *)
            echo "unknown option: $arg" >&2
            echo "usage: $0 [--release] [--no-run]" >&2
            exit 1
            ;;
    esac
done

# Make sure a stable signing identity exists before we build, so the dev
# binary is never ad-hoc signed (which is what breaks "Always Allow").
if [[ -z "${CODESIGN_IDENTITY:-}" ]] && \
   ! security find-certificate -c "$STABLE_CERT" \
        "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
    echo "==> No stable signing identity yet — creating one..."
    "$(dirname "$0")/create-signing-cert.sh"
fi

IDENTITY="${CODESIGN_IDENTITY:-$STABLE_CERT}"

echo "==> Building $PRODUCT ($CONFIG)..."
swift build -c "$CONFIG" --product "$PRODUCT"

BIN_PATH=".build/$CONFIG/$PRODUCT"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> Signing as $BUNDLE_ID with identity \"$IDENTITY\"..."
codesign --force --options runtime \
    --sign "$IDENTITY" \
    --identifier "$BUNDLE_ID" \
    "$BIN_PATH"

if [[ "$RUN_AFTER" -eq 0 ]]; then
    echo "Built and signed: $BIN_PATH"
    echo "Verify DR:  codesign -d -r- \"$BIN_PATH\""
    exit 0
fi

echo "==> Launching $BIN_PATH..."
echo "    Note: running as a loose binary (no .app bundle), so it will show"
echo "    a Dock icon during dev — this is cosmetic and pre-existing, same"
echo "    as plain 'swift run'. Launch-at-login also doesn't apply here;"
echo "    use ./Scripts/install-menubar.sh for the real installed app."
exec "$BIN_PATH"
