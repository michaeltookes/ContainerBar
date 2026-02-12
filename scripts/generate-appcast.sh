#!/bin/bash
#
# generate-appcast.sh - Generate Sparkle appcast from release archives
#
# Usage: ./scripts/generate-appcast.sh [VERSION]
#
# Prerequisites:
# - Sparkle CLI tools (download from https://github.com/sparkle-project/Sparkle/releases)
# - EdDSA private key in macOS Keychain (generated via generate_keys)
# - Signed/notarized .zip in dist/
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_ROOT/dist"
APPCAST_DIR="$PROJECT_ROOT/docs"

VERSION="${1:-}"

# Try to find generate_appcast in common locations
GENERATE_APPCAST=""
SPARKLE_LOCATIONS=(
    "$PROJECT_ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
    "/usr/local/bin/generate_appcast"
    "$HOME/Library/Developer/Sparkle/bin/generate_appcast"
)

for loc in "${SPARKLE_LOCATIONS[@]}"; do
    if [ -x "$loc" ]; then
        GENERATE_APPCAST="$loc"
        break
    fi
done

if [ -z "$GENERATE_APPCAST" ]; then
    echo "Error: generate_appcast not found."
    echo "Download Sparkle from https://github.com/sparkle-project/Sparkle/releases"
    echo "and place the CLI tools in one of these locations:"
    for loc in "${SPARKLE_LOCATIONS[@]}"; do
        echo "  - $loc"
    done
    exit 1
fi

# Verify dist directory has archives
if ! ls "$DIST_DIR"/*.zip 1>/dev/null 2>&1; then
    echo "Error: No .zip archives found in $DIST_DIR"
    echo "Run ./scripts/build-release.sh first"
    exit 1
fi

# Create docs directory if needed
mkdir -p "$APPCAST_DIR"

echo "Generating appcast..."
echo "  Tool: $GENERATE_APPCAST"
echo "  Source: $DIST_DIR"
echo "  Output: $APPCAST_DIR/appcast.xml"

# Build download URL prefix
if [ -n "$VERSION" ]; then
    DOWNLOAD_PREFIX="https://github.com/michaeltookes/ContainerBar/releases/download/v${VERSION}/"
    echo "  Download prefix: $DOWNLOAD_PREFIX"
    "$GENERATE_APPCAST" "$DIST_DIR" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        -o "$APPCAST_DIR/appcast.xml"
else
    echo "  Note: No version specified. Download URLs will use filenames only."
    echo "  Usage: ./scripts/generate-appcast.sh 1.2.0"
    "$GENERATE_APPCAST" "$DIST_DIR" \
        -o "$APPCAST_DIR/appcast.xml"
fi

echo ""
echo "Appcast generated successfully at: $APPCAST_DIR/appcast.xml"
echo ""
echo "Next steps:"
echo "  1. Review the generated appcast.xml"
echo "  2. Commit and push to main branch"
echo "  3. Ensure GitHub Pages is enabled (Settings > Pages > Source: docs/ on main)"
echo "  4. Appcast will be available at: https://michaeltookes.github.io/ContainerBar/appcast.xml"
