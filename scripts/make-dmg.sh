#!/bin/bash
# Builds the app and packages it into build/ClaudeUsageTracker.dmg with a drag-to-
# Applications layout. Honors CODESIGN_IDENTITY (defaults to ad-hoc).
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

APP="build/ClaudeUsageTracker.app"
DMG="build/ClaudeUsageTracker.dmg"
STAGING="build/dmg-staging"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Claude Usage Tracker" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"

rm -rf "$STAGING"
echo "Built $DMG"
