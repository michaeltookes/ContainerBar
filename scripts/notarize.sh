#!/bin/bash

# DockerBar Notarization Script
# This script notarizes the app with Apple and staples the ticket

set -e

# Configuration
APP_NAME="DockerBar"
BUNDLE_ID="com.tookes.DockerBar"
APPLE_ID="tookes92@att.net"
TEAM_ID="6739LM5834"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
ZIP_FILE="$OUTPUT_DIR/$APP_NAME.zip"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_info() {
    echo -e "${BLUE}Info:${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

echo_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Check requirements
check_requirements() {
    echo_step "Checking requirements..."

    if [ ! -f "$ZIP_FILE" ]; then
        echo_error "Zip file not found: $ZIP_FILE"
        echo "Please run ./scripts/build-release.sh first"
        exit 1
    fi

    # Check if app-specific password is stored in keychain
    if ! xcrun notarytool store-credentials --help &> /dev/null; then
        echo_error "notarytool not available. Please ensure Xcode is installed."
        exit 1
    fi

    echo "  ✓ Requirements met"
}

# Store credentials in keychain (one-time setup)
store_credentials() {
    echo_step "Checking notarization credentials..."

    # Check if credentials are already stored
    if xcrun notarytool history --keychain-profile "DockerBar-Notarize" &> /dev/null 2>&1; then
        echo "  ✓ Credentials already stored"
        return 0
    fi

    echo ""
    echo_info "First-time setup: You need to store your credentials in the keychain."
    echo ""
    echo "You'll need your App-Specific Password from https://appleid.apple.com"
    echo "  1. Go to Sign-In and Security → App-Specific Passwords"
    echo "  2. Generate a new password named 'DockerBar Notarization'"
    echo ""
    echo "Press Enter when ready, or Ctrl+C to cancel..."
    read

    echo_step "Storing credentials in keychain..."
    xcrun notarytool store-credentials "DockerBar-Notarize" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID"

    echo "  ✓ Credentials stored"
}

# Submit for notarization
submit_notarization() {
    echo_step "Submitting app for notarization..."
    echo "  This may take several minutes..."
    echo ""

    # Submit and wait for completion
    xcrun notarytool submit "$ZIP_FILE" \
        --keychain-profile "DockerBar-Notarize" \
        --wait

    echo ""
    echo "  ✓ Notarization submitted"
}

# Staple the notarization ticket
staple() {
    echo_step "Stapling notarization ticket to app..."

    xcrun stapler staple "$APP_BUNDLE"

    echo "  ✓ Ticket stapled"
}

# Verify notarization
verify() {
    echo_step "Verifying notarization..."

    spctl --assess --verbose=2 "$APP_BUNDLE"

    echo "  ✓ Notarization verified"
}

# Create final distributable zip
create_final_zip() {
    echo_step "Creating final distributable zip..."

    # Remove old zip
    rm -f "$ZIP_FILE"

    # Create new zip with stapled app
    cd "$OUTPUT_DIR"
    ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"

    echo "  ✓ Created: $ZIP_FILE"
}

# Create DMG (optional)
create_dmg() {
    echo_step "Creating DMG..."

    DMG_FILE="$OUTPUT_DIR/$APP_NAME.dmg"
    TEMP_DMG="$OUTPUT_DIR/temp_$APP_NAME.dmg"

    # Remove old DMG
    rm -f "$DMG_FILE" "$TEMP_DMG"

    # Create temporary DMG
    hdiutil create -srcfolder "$APP_BUNDLE" -volname "$APP_NAME" -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" -format UDRW "$TEMP_DMG"

    # Convert to compressed DMG
    hdiutil convert "$TEMP_DMG" -format UDZO -o "$DMG_FILE"

    # Remove temporary DMG
    rm -f "$TEMP_DMG"

    # Sign the DMG
    codesign --force --sign "Developer ID Application: MICHAEL ARRINGTON TOOKES (6739LM5834)" "$DMG_FILE"

    # Notarize the DMG
    echo "  Notarizing DMG..."
    xcrun notarytool submit "$DMG_FILE" \
        --keychain-profile "DockerBar-Notarize" \
        --wait

    # Staple the DMG
    xcrun stapler staple "$DMG_FILE"

    echo "  ✓ Created: $DMG_FILE"
}

# Print summary
summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Notarization Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Your app is now signed, notarized, and ready for distribution!"
    echo ""
    echo "Output files:"
    echo "  App Bundle: $APP_BUNDLE"
    echo "  Zip File:   $ZIP_FILE"
    if [ -f "$OUTPUT_DIR/$APP_NAME.dmg" ]; then
        echo "  DMG File:   $OUTPUT_DIR/$APP_NAME.dmg"
    fi
    echo ""
    echo "Users can now download and run the app without Gatekeeper warnings."
    echo ""
}

# Main
main() {
    echo ""
    echo "DockerBar Notarization"
    echo "======================"
    echo ""

    check_requirements
    store_credentials
    submit_notarization
    staple
    verify
    create_final_zip

    # Ask about DMG creation
    echo ""
    read -p "Would you like to create a DMG file as well? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_dmg
    fi

    summary
}

main "$@"
