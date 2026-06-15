#!/bin/bash
# Builds ClaudeUsageTracker.app into build/ (no Xcode required).
# Set CODESIGN_IDENTITY to a Developer ID for a distributable, notarizable build;
# otherwise the app is ad-hoc signed (fine for local use).
set -euo pipefail
cd "$(dirname "$0")/.."

# Ensure the icon exists.
[ -f Resources/AppIcon.icns ] || ./scripts/build-icon.sh

swift build -c release

APP="build/ClaudeUsageTracker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp .build/release/ClaudeUsageTracker "$APP/Contents/MacOS/ClaudeUsageTracker"

IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$APP"
else
  # Hardened runtime is required for notarization.
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "Built $APP (signed with: $IDENTITY)"
