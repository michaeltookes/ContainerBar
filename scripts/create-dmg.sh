#!/bin/bash

# ContainerBar DMG Creation Script
# Creates a styled DMG with app icon and Applications folder shortcut

set -e

# Configuration
APP_NAME="ContainerBar"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/Distribution"
OUTPUT_DIR="$PROJECT_ROOT/dist"

# Read version from Info.plist (single source of truth)
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DIST_DIR/Info.plist")
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
DMG_OUTPUT="$OUTPUT_DIR/$APP_NAME.dmg"
BACKGROUND_IMG="$DIST_DIR/dmg-background.png"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Check requirements
if ! command -v create-dmg &> /dev/null; then
    echo_error "create-dmg is not installed. Install with: brew install create-dmg"
    exit 1
fi

if [ ! -d "$APP_BUNDLE" ]; then
    echo_error "App bundle not found at $APP_BUNDLE"
    echo "Run ./scripts/build-release.sh first"
    exit 1
fi

# Generate background if it doesn't exist
if [ ! -f "$BACKGROUND_IMG" ]; then
    echo_step "Generating DMG background..."
    swift "$SCRIPT_DIR/generate-dmg-background.swift"
fi

# Remove existing DMG
rm -f "$DMG_OUTPUT"

echo_step "Creating styled DMG..."

# Create the DMG with create-dmg
create-dmg \
    --volname "$APP_NAME" \
    --volicon "$DIST_DIR/AppIcon.icns" \
    --background "$BACKGROUND_IMG" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "$APP_NAME.app" 170 190 \
    --hide-extension "$APP_NAME.app" \
    --app-drop-link 490 190 \
    "$DMG_OUTPUT" \
    "$APP_BUNDLE"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}DMG Created Successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Output: $DMG_OUTPUT"
echo ""
echo "Next steps:"
echo "  1. Open the DMG to verify it looks correct"
echo "  2. Run ./scripts/notarize.sh to notarize for distribution"
echo ""
