#!/bin/bash
#
# Quick setup script to build, install, and configure GroundLoop with launch-at-login.
#
# This script:
# 1. Builds GroundLoop.app bundle
# 2. Installs it to /Applications
# 3. Launches the app
# 4. Opens System Preferences so you can verify launch-at-login is enabled
#
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building and installing GroundLoop..."
"./Scripts/install-menubar.sh"

echo ""
echo "==> Setup complete!"
echo ""
echo "GroundLoop is now installed in /Applications."
echo "The 'Launch at login' option is available in:"
echo "  1. Right-click the menubar icon → 'Launch at Login'"
echo "  2. Preferences → General → 'Launch at login'"
echo ""
echo "Note: Launch-at-login requires the app to be installed as a .app bundle."
echo "It won't work when running via 'swift run'."
