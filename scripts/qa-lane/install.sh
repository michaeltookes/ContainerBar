#!/bin/zsh
# Install the ContainerBar QA lane tooling into Lucius' workspace (CB-105).
# Dry run by default: prints every action. --apply performs them.
#
#   install.sh [--apply] [--with-cron --brief tasks/<date>-containerbar-daily.md]
#
# Private values are read from $WS/qa/containerbar/lane.env, never from this repo:
#   CBQA_RUNNER_NAMES   runner names registered on this host (comma separated)
#   CBQA_ALERT_TARGET   Discord target for #lucius-updates lines
#   CBQA_DAILY_TARGET   Discord target the daily pass announces to
# The hourly webhook lives in ~/.openclaw/.env as CONTAINERBAR_QA_WEBHOOK.
set -eu
here=${0:A:h}
ws=${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}
tools=$ws/tools/containerbar-qa
agent=$HOME/Library/LaunchAgents/com.genkeilabs.containerbar-hourly.plist
apply=0; with_cron=0; brief=""
while [ $# -gt 0 ]; do
  case $1 in
    --apply) apply=1 ;;
    --with-cron) with_cron=1 ;;
    --brief) shift; brief=$1 ;;
    *) echo "unknown option $1" >&2; exit 64 ;;
  esac
  shift
done

doit() { if [ $apply = 1 ]; then "$@"; else print -r -- "dry-run: ${(q)@}"; fi }

intervals=""
for h in {8..20}; do
  intervals+="    <dict><key>Hour</key><integer>$h</integer><key>Minute</key><integer>40</integer></dict>"$'\n'
done
rendered=$(mktemp -t containerbar-hourly)
sed -e "s|__TOOLS__|$tools|g" -e "s|__HOME__|$HOME|g" "$here/com.genkeilabs.containerbar-hourly.plist.template" \
  | awk -v iv="$intervals" '{ if ($0 == "__INTERVALS__") printf "%s", iv; else print }' > "$rendered"
plutil -lint "$rendered" >/dev/null

doit mkdir -p "$tools" "$ws/qa/containerbar" "$ws/artifacts/containerbar-qa" "$HOME/Library/Logs/containerbar-qa"
for f in cbqa_lane.py lane_core.py lane_restore.py lane_preflight.py lane_hourly.py lane_prefs.py \
         containerbar-qa-restore.sh containerbar-hourly.sh README.md; do
  doit cp "$here/$f" "$tools/$f"
done
doit cp "$rendered" "$agent"
doit launchctl bootout "gui/$(id -u)/com.genkeilabs.containerbar-hourly" || true
doit launchctl bootstrap "gui/$(id -u)" "$agent"
rm -f "$rendered"

if [ $with_cron = 1 ]; then
  [ -n "$brief" ] || { echo "--with-cron needs --brief tasks/<file>.md" >&2; exit 64; }
  target=$(grep '^CBQA_DAILY_TARGET=' "$ws/qa/containerbar/lane.env" 2>/dev/null | tail -n1 | cut -d= -f2-)
  [ -n "$target" ] || { echo "CBQA_DAILY_TARGET missing from lane.env" >&2; exit 64; }
  doit openclaw cron add --name "ContainerBar daily QA" --declaration-key containerbar-daily-qa \
    --cron "5 7 * * *" --tz America/Chicago --exact --session isolated --model openai/gpt-6-astra \
    --timeout-seconds 1800 --announce --channel discord --to "$target" \
    --message "Run the ContainerBar daily QA pass. Read $brief and follow it exactly, starting with its Environment preamble."
fi
