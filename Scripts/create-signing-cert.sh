#!/bin/bash
#
# Create a stable, self-signed code-signing certificate for GroundLoop.
#
# WHY: macOS Keychain pins an app's *code signature* in an item's ACL when
# you click "Always Allow". An ad-hoc signature (the SwiftPM default) gets a
# brand-new code hash on every build, so the saved "Always Allow" no longer
# matches after a rebuild and the password prompt reappears forever.
#
# Signing every build with the SAME self-signed certificate gives the app a
# STABLE identity, so "Always Allow" sticks permanently across rebuilds.
#
# One-time setup. No sudo and no Apple Developer account required.
# Safe to re-run: it re-creates nothing that already exists.
#
set -euo pipefail

CERT_NAME="GroundLoop Code Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if ! security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "==> Creating self-signed code-signing certificate \"$CERT_NAME\"..."

    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT

    # Self-signed cert + key, valid 10 years, marked for code signing.
    # (LibreSSL's default PKCS#12 encoding is the one macOS `security` reads.)
    openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -days 3650 \
        -subj "/CN=$CERT_NAME" \
        -addext "basicConstraints=critical,CA:false" \
        -addext "keyUsage=critical,digitalSignature" \
        -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

    openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
        -name "$CERT_NAME" -out "$TMP/cert.p12" -passout pass:groundloop >/dev/null 2>&1

    # -A lets /usr/bin/codesign use the private key.
    security import "$TMP/cert.p12" -k "$KEYCHAIN" -P groundloop -A >/dev/null
    echo "    Certificate created and imported."
else
    echo "==> Certificate \"$CERT_NAME\" already exists."
fi

# Allow codesign to use the key WITHOUT a per-build "wants to sign" prompt.
# This sets the keychain partition list and needs your macOS login password
# ONCE (typed straight into `security`, never seen by any script).
echo "==> Authorizing codesign to use the key (enter your Mac login password)..."
if security set-key-partition-list -S apple-tool:,apple: -s \
        -l "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "    Done — builds will sign silently."
else
    echo "    (Skipped/declined. Not fatal: on your first signed build you'll"
    echo "     see one 'codesign wants to use key' prompt — click 'Always Allow'"
    echo "     once and it never returns.)"
fi

echo
echo "Signing identity \"$CERT_NAME\" is ready."
echo "Next: ./Scripts/install-menubar.sh"
