#!/bin/bash
# Builds ClaudeUsageTracker.app into build/ (no Xcode required).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/ClaudeUsageTracker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp .build/release/ClaudeUsageTracker "$APP/Contents/MacOS/ClaudeUsageTracker"
codesign --force --sign - "$APP"

echo "Built $APP"
