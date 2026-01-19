#!/bin/bash

# DockerBar Release Build Script
# This script builds, signs, and packages DockerBar for distribution

set -e

# Configuration
APP_NAME="DockerBar"
BUNDLE_ID="com.tookes.DockerBar"
VERSION="1.0.0"
BUILD_NUMBER="1"

# Signing identity - Developer ID Application certificate
SIGNING_IDENTITY="Developer ID Application: MICHAEL ARRINGTON TOOKES (6739LM5834)"
TEAM_ID="6739LM5834"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/.build/release"
DIST_DIR="$PROJECT_ROOT/Distribution"
OUTPUT_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

echo_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Check for required tools
check_requirements() {
    echo_step "Checking requirements..."

    if ! command -v swift &> /dev/null; then
        echo_error "Swift is not installed"
        exit 1
    fi

    if ! command -v codesign &> /dev/null; then
        echo_error "codesign is not available"
        exit 1
    fi

    # Check if signing identity exists
    if ! security find-identity -v -p codesigning | grep -q "$TEAM_ID"; then
        echo_error "Developer ID Application certificate not found for team $TEAM_ID"
        echo "Please ensure you have created the certificate in Xcode:"
        echo "  1. Open Xcode → Settings → Accounts"
        echo "  2. Select your team and click 'Manage Certificates'"
        echo "  3. Click '+' and select 'Developer ID Application'"
        exit 1
    fi

    echo "  ✓ All requirements met"
}

# Clean previous builds
clean() {
    echo_step "Cleaning previous builds..."
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    echo "  ✓ Cleaned"
}

# Build the app in release mode
build() {
    echo_step "Building $APP_NAME in release mode..."
    cd "$PROJECT_ROOT"
    swift build -c release
    echo "  ✓ Build complete"
}

# Create the app bundle structure
create_bundle() {
    echo_step "Creating app bundle..."

    # Create bundle structure
    mkdir -p "$APP_BUNDLE/Contents/MacOS"
    mkdir -p "$APP_BUNDLE/Contents/Resources"

    # Copy executable
    cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

    # Copy Info.plist
    cp "$DIST_DIR/Info.plist" "$APP_BUNDLE/Contents/"

    # Update version in Info.plist
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"

    # Copy any frameworks if needed (Sparkle, etc.)
    if [ -d "$BUILD_DIR/Sparkle.framework" ]; then
        mkdir -p "$APP_BUNDLE/Contents/Frameworks"
        cp -R "$BUILD_DIR/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/"
    fi

    echo "  ✓ Bundle created"
}

# Sign the app
sign() {
    echo_step "Signing app bundle..."

    # Sign Sparkle framework components in the correct order (deepest first)
    SPARKLE_FW="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    if [ -d "$SPARKLE_FW" ]; then
        echo "  Signing Sparkle framework components..."

        # Sign the Autoupdate binary
        if [ -f "$SPARKLE_FW/Versions/B/Autoupdate" ]; then
            echo "    Signing: Autoupdate"
            codesign --force --options runtime --timestamp \
                --sign "$SIGNING_IDENTITY" \
                "$SPARKLE_FW/Versions/B/Autoupdate"
        fi

        # Sign XPC services
        for xpc in "$SPARKLE_FW/Versions/B/XPCServices"/*.xpc; do
            if [ -d "$xpc" ]; then
                echo "    Signing: $(basename "$xpc")"
                codesign --force --options runtime --timestamp \
                    --sign "$SIGNING_IDENTITY" \
                    "$xpc"
            fi
        done

        # Sign Updater.app
        if [ -d "$SPARKLE_FW/Versions/B/Updater.app" ]; then
            echo "    Signing: Updater.app"
            codesign --force --options runtime --timestamp \
                --sign "$SIGNING_IDENTITY" \
                "$SPARKLE_FW/Versions/B/Updater.app"
        fi

        # Sign the main Sparkle framework
        echo "    Signing: Sparkle.framework"
        codesign --force --options runtime --timestamp \
            --sign "$SIGNING_IDENTITY" \
            "$SPARKLE_FW"
    fi

    # Sign any other frameworks or dylibs
    if [ -d "$APP_BUNDLE/Contents/Frameworks" ]; then
        find "$APP_BUNDLE/Contents/Frameworks" -name "*.dylib" | while read dylib; do
            echo "  Signing: $(basename "$dylib")"
            codesign --force --options runtime --timestamp \
                --sign "$SIGNING_IDENTITY" \
                "$dylib"
        done
    fi

    # Sign the main app bundle
    echo "  Signing: $APP_NAME.app"
    codesign --force --options runtime --timestamp \
        --entitlements "$DIST_DIR/DockerBar.entitlements" \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE"

    echo "  ✓ Signing complete"
}

# Verify the signature
verify() {
    echo_step "Verifying signature..."

    codesign --verify --verbose=2 "$APP_BUNDLE"
    echo ""
    codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1 | grep -E "(Authority|TeamIdentifier|Signature)"

    echo "  ✓ Signature verified"
}

# Create a zip for notarization
create_zip() {
    echo_step "Creating zip for distribution..."

    cd "$OUTPUT_DIR"
    ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"

    echo "  ✓ Created: $OUTPUT_DIR/$APP_NAME.zip"
}

# Print summary
summary() {
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Build Complete!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Output files:"
    echo "  App Bundle: $APP_BUNDLE"
    echo "  Zip File:   $OUTPUT_DIR/$APP_NAME.zip"
    echo ""
    echo "Next steps:"
    echo "  1. Run: ./scripts/notarize.sh"
    echo "  2. Wait for notarization to complete"
    echo "  3. Distribute the app!"
    echo ""
}

# Main
main() {
    echo ""
    echo "DockerBar Release Build"
    echo "======================="
    echo ""

    check_requirements
    clean
    build
    create_bundle
    sign
    verify
    create_zip
    summary
}

main "$@"
