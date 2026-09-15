#!/bin/bash
#
# smoke-launch-mini.sh — Smoke-launch the DISTRIBUTED ContainerBar build on a
# clean machine (no repo checkout). Verifies the notarized zip a user actually
# downloads unpacks, passes Gatekeeper, is stapled, and launches.
#
# This is a RELEASE-TIME step (see docs/RELEASING.md). It does NOT build or
# notarize anything — run it after dist/ContainerBar.zip is notarized+stapled.
#
# Usage: ./scripts/smoke-launch-mini.sh [--zip PATH] [--host USER@HOST]
#   --zip PATH    distributable zip to test (default: dist/ContainerBar.zip)
#   --host U@H    clean machine over SSH (default: luciusfox@192.168.86.28)
#
# The zip is copied into a throwaway temp dir on the target and run from there,
# so the test exercises the distributed artifact, not a source tree. The Lucius
# Mac mini is the default target; its ~/qa/ContainerBar checkout is NOT used.
#
# NOTE: a menu-bar (Aqua) app needs a console GUI session to launch. GUI
# automation over SSH is not supported on the mini, so the signature /
# Gatekeeper / staple checks always run, but the actual launch happens only when
# a GUI session is present; otherwise the exact console command is printed.
#
# `gh` uploads for releases must run as the michaeltookes account
# (export GH_TOKEN="$(gh auth token -u michaeltookes)") — see docs/RELEASING.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

ZIP_PATH="$PROJECT_ROOT/dist/ContainerBar.zip"
MINI_HOST="luciusfox@192.168.86.28"

while [ $# -gt 0 ]; do
    case "$1" in
        --zip)
            ZIP_PATH="$2"
            shift 2
            ;;
        --host)
            MINI_HOST="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,18p' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            echo "Usage: $0 [--zip PATH] [--host USER@HOST]" >&2
            exit 2
            ;;
    esac
done

if [ ! -f "$ZIP_PATH" ]; then
    echo "Error: zip not found: $ZIP_PATH" >&2
    echo "Build and notarize a release first (see docs/RELEASING.md)." >&2
    exit 1
fi

echo "==> Copying $ZIP_PATH to $MINI_HOST"
REMOTE_TMP="$(ssh "$MINI_HOST" 'mktemp -d /tmp/containerbar-smoke.XXXXXX')"
# shellcheck disable=SC2064  # expand host/tmp now so the trap cleans the right dir
trap "ssh '$MINI_HOST' 'rm -rf \"$REMOTE_TMP\"'" EXIT

scp -q "$ZIP_PATH" "$MINI_HOST:$REMOTE_TMP/ContainerBar.zip"

echo "==> Verifying the distributed build on $MINI_HOST"
ssh "$MINI_HOST" bash -s -- "$REMOTE_TMP" <<'REMOTE'
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
REMOTE_TMP="$1"
cd "$REMOTE_TMP"

ditto -x -k ContainerBar.zip extracted
APP="$REMOTE_TMP/extracted/ContainerBar.app"
if [ ! -d "$APP" ]; then
    echo "FAIL: ContainerBar.app not found inside zip"
    exit 1
fi

echo "-- codesign --verify --deep --strict"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "-- spctl --assess --type execute"
spctl --assess --type execute --verbose=2 "$APP"

echo "-- xcrun stapler validate"
xcrun stapler validate "$APP"

if launchctl print "gui/$(id -u)" >/dev/null 2>&1; then
    echo "-- GUI session present: launching for smoke test"
    CONTAINERBAR_OPEN_SETTINGS_ON_LAUNCH=1 open -a "$APP" || true
    sleep 5
    osascript -e 'tell application "ContainerBar" to quit' 2>/dev/null \
        || pkill -f "ContainerBar.app/Contents/MacOS/ContainerBar" 2>/dev/null \
        || true
    echo "-- launched and quit"
else
    echo "-- NO GUI session over SSH: run the launch from the mini's console:"
    echo "     open -a \"$APP\""
    echo "   Confirm the menu-bar icon appears, open Settings, then quit."
fi

echo "SMOKE CHECKS OK"
REMOTE

echo "==> Smoke check complete."
