#!/bin/bash
# CB-135: run resign.sh inside the gui/501 launchd context from an SSH/agent shell.
#
#   CBQA_LOCK_TOKEN="$TOKEN" bash tools/containerbar-qa/resign-gui.sh <candidate.app> <branch-sha>
#
# Bootstraps a one-shot LaunchAgent into gui/<uid> (the only context where the login keychain is unlocked),
# runs resign.sh there, boots the agent out, deletes the plist, prints resign.sh's output and exits with its exit code unchanged.
# The token reaches the job through the plist's EnvironmentVariables (mode 600, removed before exit); it is never printed or logged.
# No token or a bad token is passed through as-is: resign.sh itself ends BLOCKED desktop-busy (exit 7).
# Exit 9: this wrapper could not start or collect the job (not a resign.sh verdict).
set -u
here=$(cd "$(dirname "$0")" && pwd)
ws=${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}
launchctl_bin=${CBQA_LAUNCHCTL:-launchctl}
uid=${CBQA_UID:-$(id -u)}
timeout_s=${CBQA_RESIGN_TIMEOUT:-300}

if [ "${1:-}" = "--inner" ]; then
  # Runs inside gui/501: $2 = result dir, rest = resign.sh arguments.
  out=$2; shift 2
  bash "$here/resign.sh" "$@" >"$out/output.txt" 2>&1
  echo $? >"$out/rc.tmp" && mv "$out/rc.tmp" "$out/rc"
  exit 0
fi

[ $# -eq 2 ] || { echo "usage: CBQA_LOCK_TOKEN=... resign-gui.sh <candidate.app> <branch-sha>" >&2; exit 64; }
case "${CBQA_LOCK_TOKEN:-}" in
  *[!A-Za-z0-9._-]*) echo "resign-gui: lock token has unexpected characters" >&2; exit 64 ;;
esac
for a in "$1" "$2" "$here" "$ws"; do
  case "$a" in *[\<\>\&\"\']*) echo "resign-gui: unsafe character in an argument or path" >&2; exit 64 ;; esac
done

umask 077
base=$ws/artifacts/containerbar-qa/resign-gui
mkdir -p "$base" || exit 9
dir=$(mktemp -d "$base/run.XXXXXX") || exit 9
label=com.genkeilabs.containerbar-resign.$$
plist=$dir/$label.plist
cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$here/resign-gui.sh</string><string>--inner</string><string>$dir</string>
    <string>$1</string><string>$2</string>
  </array>
  <key>EnvironmentVariables</key><dict>
    <key>CBQA_LOCK_TOKEN</key><string>${CBQA_LOCK_TOKEN:-}</string>
    <key>CBQA_WORKSPACE</key><string>$ws</string>
  </dict>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST

cleanup() { "$launchctl_bin" bootout "gui/$uid/$label" >/dev/null 2>&1 || true; rm -f "$plist"; }
trap cleanup EXIT
"$launchctl_bin" bootstrap "gui/$uid" "$plist" >/dev/null 2>&1 || { echo "resign-gui: launchctl bootstrap failed" >&2; exit 9; }
waited=0
while [ ! -f "$dir/rc" ]; do
  [ "$waited" -ge "$timeout_s" ] && { echo "resign-gui: timed out waiting for resign.sh" >&2; exit 9; }
  sleep 1; waited=$((waited + 1))
done
cat "$dir/output.txt" 2>/dev/null
rc=$(cat "$dir/rc")
rm -rf "$dir"
exit "${rc:-9}"
