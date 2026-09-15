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
#   --host U@H    clean machine over SSH (default: $SMOKE_HOST; required)
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
# The target is deliberately not hardcoded: this repo is public, so the
# clean machine's address comes from --host or the SMOKE_HOST env var.
MINI_HOST="${SMOKE_HOST:-}"

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

if [ -z "$MINI_HOST" ]; then
    echo "No target machine: pass --host USER@HOST or set SMOKE_HOST." >&2
    exit 2
fi

echo "==> Copying $ZIP_PATH to $MINI_HOST"
REMOTE_TMP="$(ssh "$MINI_HOST" 'mktemp -d /tmp/containerbar-smoke.XXXXXX')"
PRESERVE_REMOTE_TMP=0

cleanup_remote_tmp() {
    if [ -z "${REMOTE_TMP:-}" ]; then
        return
    fi
    if [ "$PRESERVE_REMOTE_TMP" -eq 1 ]; then
        echo "==> Remote smoke artifact preserved at $MINI_HOST:$REMOTE_TMP"
        echo "==> After manual verification, clean it up with:"
        echo "    ssh \"$MINI_HOST\" 'rm -rf \"$REMOTE_TMP\"'"
        return
    fi
    ssh "$MINI_HOST" "rm -rf \"$REMOTE_TMP\"" || true
}

trap cleanup_remote_tmp EXIT

scp -q "$ZIP_PATH" "$MINI_HOST:$REMOTE_TMP/ContainerBar.zip"

echo "==> Verifying the distributed build on $MINI_HOST"
set +e
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
APP_EXEC="$APP/Contents/MacOS/ContainerBar"
if [ ! -x "$APP_EXEC" ]; then
    echo "FAIL: ContainerBar executable not found inside app bundle"
    exit 1
fi
APP_EXEC_DIR="$(cd "$(dirname "$APP_EXEC")" && pwd -P)"
REAL_APP_EXEC="$APP_EXEC_DIR/$(basename "$APP_EXEC")"

is_containerbar_running() {
    pgrep -f "$APP_EXEC" >/dev/null 2>&1 \
        || pgrep -f "$REAL_APP_EXEC" >/dev/null 2>&1 \
        || pgrep -x "ContainerBar" >/dev/null 2>&1
}

quit_containerbar() {
    osascript -e 'tell application "ContainerBar" to quit' 2>/dev/null \
        || pkill -f "$APP_EXEC" 2>/dev/null \
        || pkill -f "$REAL_APP_EXEC" 2>/dev/null \
        || pkill -x "ContainerBar" 2>/dev/null \
        || true
}

echo "-- codesign --verify --deep --strict"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "-- spctl --assess --type execute"
spctl --assess --type execute --verbose=2 "$APP"

echo "-- xcrun stapler validate"
xcrun stapler validate "$APP"

if launchctl print "gui/$(id -u)" >/dev/null 2>&1; then
    echo "-- GUI session present: launching for smoke test"
    if is_containerbar_running; then
        echo "FAIL: ContainerBar is already running; quit it before smoke testing this artifact"
        exit 1
    fi
    if ! CONTAINERBAR_OPEN_SETTINGS_ON_LAUNCH=1 open -a "$APP"; then
        echo "FAIL: open could not launch ContainerBar"
        exit 1
    fi
    sleep 5
    if ! is_containerbar_running; then
        echo "FAIL: ContainerBar is not running after launch"
        quit_containerbar
        exit 1
    fi
    quit_containerbar
    echo "-- launched and quit"
else
    echo "-- NO GUI session over SSH: run the launch from the mini's console:"
    echo "     open -a \"$APP\""
    echo "   Confirm the menu-bar icon appears, open Settings, then quit."
    echo "   Then remove the preserved smoke directory:"
    echo "     rm -rf \"$REMOTE_TMP\""
    exit 90
fi

echo "SMOKE CHECKS OK"
REMOTE
REMOTE_STATUS=$?
set -e

if [ "$REMOTE_STATUS" -eq 90 ]; then
    PRESERVE_REMOTE_TMP=1
    echo "==> Signature, Gatekeeper, and stapler checks passed."
    echo "==> Manual console launch is still required; see the command above."
    exit 90
fi

if [ "$REMOTE_STATUS" -ne 0 ]; then
    exit "$REMOTE_STATUS"
fi

echo "==> Smoke check complete."
