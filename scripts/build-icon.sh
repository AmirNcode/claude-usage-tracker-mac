#!/bin/bash
# Renders the app icon (build/AppIcon.iconset) and compiles Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p build Resources
swift scripts/gen-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
echo "Built Resources/AppIcon.icns"
