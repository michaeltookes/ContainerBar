#!/bin/bash
#
# build-hunt-app.sh - Build an unsigned Debug ContainerBar.app for Prowl hunts.
#
# Output: .prowl/DerivedData/Build/Products/Debug/ContainerBar.app
#
# The `.prowl/DerivedData` path segment is what switches the app into hunt mode
# (Sources/ContainerBar/Services/HuntMode.swift): fixture Docker client, throwaway
# preferences, no real hosts. Do not relocate the output.
set -euo pipefail

APP_NAME="ContainerBar"
HUNT_BUNDLE_ID="com.tookes.ContainerBar.hunt"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DERIVED_DATA="$PROJECT_ROOT/.prowl/DerivedData"
BUILD_DIR="$DERIVED_DATA/Build/Products/Debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
DIST_DIR="$PROJECT_ROOT/Distribution"

echo "==> Building $APP_NAME (Debug) into $DERIVED_DATA"
cd "$PROJECT_ROOT"
set +e
xcodebuild \
    -scheme "$APP_NAME" \
    -configuration Debug \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
build_statuses=("${PIPESTATUS[@]}")
set -e

xcodebuild_status="${build_statuses[0]}"
if [ "$xcodebuild_status" -ne 0 ]; then
    echo "Error: xcodebuild failed with exit code $xcodebuild_status" >&2
    exit "$xcodebuild_status"
fi

if [ ! -x "$BUILD_DIR/$APP_NAME" ]; then
    echo "Error: xcodebuild did not produce $BUILD_DIR/$APP_NAME" >&2
    exit 1
fi

echo "==> Assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "$DIST_DIR/Info.plist" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $HUNT_BUNDLE_ID" "$INFO_PLIST"
[ -f "$DIST_DIR/AppIcon.icns" ] && cp "$DIST_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

for bundle in "$BUILD_DIR"/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$APP_BUNDLE/Contents/Resources/"
done
for required in ContainerBar_ContainerBar.bundle KeyboardShortcuts_KeyboardShortcuts.bundle; do
    if [ ! -d "$APP_BUNDLE/Contents/Resources/$required" ]; then
        echo "Error: $required missing from build products" >&2
        exit 1
    fi
done

if [ -d "$BUILD_DIR/Sparkle.framework" ]; then
    cp -R "$BUILD_DIR/Sparkle.framework" "$APP_BUNDLE/Contents/Frameworks/"
fi
BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
if ! otool -l "$BINARY" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath @executable_path/../Frameworks "$BINARY"
fi

# Ad-hoc signature so the bundle launches locally and on the runner.
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1

echo "==> Ready: $APP_BUNDLE"
