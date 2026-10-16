#!/bin/zsh
# ContainerBar hourly QA check (CB-105). launchd com.genkeilabs.containerbar-hourly.
# Zero tokens, no AppleScript, no GUI. Takes the shared desktop lock; when a pass
# or another desktop brief holds it (lock tool exit 75) the run is skipped.
set -u
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
here=${0:A:h}
py=${CBQA_PYTHON:-/usr/bin/python3}
ws=${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}
lock_tool=${CBQA_LOCK_TOOL:-$ws/tools/sentwise-qa/device_lock.py}
lock_dir=${CBQA_LOCK_DIR:-$ws/artifacts/sentwise-qa/device.lock}
job=launchd:com.genkeilabs.containerbar-hourly
run=containerbar-hourly-$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$ws/artifacts/containerbar-qa"

"$py" -B "$lock_tool" --lock "$lock_dir" --run "$run" --session "$job" --job "$job" \
  --timeout 55 --grace 2 -- "$py" -B "$here/cbqa_lane.py" hourly-checks "$@"
rc=$?
case $rc in
  0) ;;
  75) "$py" -B "$here/cbqa_lane.py" hourly-log "skipped desktop-busy" ;;
  124) "$py" -B "$here/cbqa_lane.py" hourly-log "timeout after 55s" ;;
  *) "$py" -B "$here/cbqa_lane.py" hourly-log "error rc=$rc" ;;
esac
exit 0
