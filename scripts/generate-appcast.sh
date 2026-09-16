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
    "$PROJECT_ROOT/.build/xcode-release/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
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

# Sparkle's generate_appcast fails with a duplicate-update error when it finds
# two archives for the same version in one directory (e.g. both
# ContainerBar.zip and ContainerBar.dmg, as the 2.0.4 release had). Stage ONLY
# the zip(s) in a temp dir and generate from there, so the signed DMG can still
# live in dist/ for the GitHub release without breaking appcast generation.
# The existing appcast is copied into the stage first so generate_appcast
# preserves prior version entries (merged back into docs/appcast.xml) instead
# of dropping them.
STAGE_DIR="$(mktemp -d)"
cleanup() { rm -rf "$STAGE_DIR"; }
trap cleanup EXIT

cp "$DIST_DIR"/*.zip "$STAGE_DIR"/
if [ -f "$APPCAST_DIR/appcast.xml" ]; then
    cp "$APPCAST_DIR/appcast.xml" "$STAGE_DIR/appcast.xml"
fi

echo "Generating appcast..."
echo "  Tool: $GENERATE_APPCAST"
echo "  Source: $STAGE_DIR (zip only; DMG excluded to avoid duplicate-update error)"
echo "  Output: $APPCAST_DIR/appcast.xml"

# Build download URL prefix
if [ -n "$VERSION" ]; then
    DOWNLOAD_PREFIX="https://github.com/michaeltookes/ContainerBar/releases/download/v${VERSION}/"
    echo "  Download prefix: $DOWNLOAD_PREFIX"
    "$GENERATE_APPCAST" "$STAGE_DIR" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        -o "$APPCAST_DIR/appcast.xml"
else
    echo "  Note: No version specified. Download URLs will use filenames only."
    echo "  Usage: ./scripts/generate-appcast.sh 1.2.0"
    "$GENERATE_APPCAST" "$STAGE_DIR" \
        -o "$APPCAST_DIR/appcast.xml"
fi

echo "Adding arm64 hardware requirement to appcast entries..."
python3 - "$APPCAST_DIR/appcast.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"
HARDWARE_TAG = f"{{{SPARKLE_NS}}}hardwareRequirements"
MINIMUM_SYSTEM_TAG = f"{{{SPARKLE_NS}}}minimumSystemVersion"

ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)

path = sys.argv[1]
tree = ET.parse(path)
root = tree.getroot()

for item in root.findall(".//item"):
    hardware = item.find(HARDWARE_TAG)
    if hardware is not None:
        hardware.text = "arm64"
        continue

    hardware = ET.Element(HARDWARE_TAG)
    hardware.text = "arm64"
    insert_at = len(item)
    for index, child in enumerate(list(item)):
        if child.tag == MINIMUM_SYSTEM_TAG:
            insert_at = index
            break
    item.insert(insert_at, hardware)

if hasattr(ET, "indent"):
    ET.indent(tree, space="    ")
tree.write(path, encoding="utf-8", xml_declaration=True)
PY

echo ""
echo "Appcast generated successfully at: $APPCAST_DIR/appcast.xml"
echo ""
echo "Next steps:"
echo "  1. Review the generated appcast.xml"
echo "  2. Commit and push to main branch"
echo "  3. Ensure GitHub Pages is enabled (Settings > Pages > Source: docs/ on main)"
echo "  4. Appcast will be available at: https://michaeltookes.github.io/ContainerBar/appcast.xml"
