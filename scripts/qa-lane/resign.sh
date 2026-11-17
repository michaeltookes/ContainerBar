#!/bin/bash
# Re-sign a branch build with the QA Apple Development identity and check its provenance (CB-124).
#   resign.sh <candidate.app> <branch-sha>   stage, sign, verify, then replace the installed app
#   resign.sh --provenance                   print key=value lines, last one provenance=ok|FAIL <why>
# Exit codes: 0 ok, 1 provenance FAIL, 3 BLOCKED qa-signing-failed, 4 BLOCKED qa-identity-invalid,
# 5 BLOCKED app-quit-timeout (installed app would not quit), 6 BLOCKED keychain-locked, 7 BLOCKED desktop-busy or
# ci-busy, 8 BLOCKED qa-install-failed (copy, swap or provenance record failed; the previous install is kept), 64 usage.
# The caller must hold the shared desktop lock: pass its token in CBQA_LOCK_TOKEN (preflight's "lock token").
# The identity is selected by SHA-1 hash from CBQA_SIGNING_IDENTITY_HASH in $WS/qa/containerbar/lane.env
# (homelab-it sets it; the value never enters the repo). Run only from the lane's launchd (gui) context.
set -u
ws=${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}
dir=$ws/qa/containerbar
app=${CBQA_APP_PATH:-/Applications/ContainerBar.app}
stage=$ws/artifacts/containerbar-qa/staged
record=$dir/branch-candidate.env
ent=$dir/ContainerBar.entitlements
here=$(cd "$(dirname "$0")" && pwd)

conf() { grep "^$1=" "$dir/lane.env" 2>/dev/null | tail -n1 | cut -d= -f2-; }
vb() { printf '%s-%s' "$(plutil -extract CFBundleShortVersionString raw -o - "$1/Contents/Info.plist")" \
  "$(plutil -extract CFBundleVersion raw -o - "$1/Contents/Info.plist")"; }
rec() { grep "^$1=" "$record" 2>/dev/null | tail -n1 | cut -d= -f2-; }
# SHA-1 of the leaf certificate the bundle is signed with (upper case, no colons).
signed_hash() {
  local t; t=$(mktemp -d "${TMPDIR:-/tmp}/cbqa-cert.XXXXXX") || return 1
  codesign -d --extract-certificates="$t/cert" "$1" >/dev/null 2>&1
  openssl x509 -inform der -in "$t/cert0" -noout -fingerprint -sha1 2>/dev/null | sed 's/.*=//; s/://g'
  rm -f "$t/cert0" "$t/cert1" "$t/cert2" "$t/cert3"; rmdir "$t" 2>/dev/null
}
plist_id() { plutil -extract CFBundleIdentifier raw -o - "$1/Contents/Info.plist" 2>/dev/null; }
signed_id() { codesign -dvv "$1" 2>&1 | sed -n 's/^Identifier=//p' | head -n1; }
apple_dev() { codesign -dvv "$1" 2>&1 | grep '^Authority=' | head -n1 | grep -q '^Authority=Apple Development'; }
valid_hash() {
  [[ $1 =~ ^[0-9A-Fa-f]{40}$ ]] && security find-identity -v -p codesigning 2>/dev/null | grep -qi "$1"
}

if [ "${1:-}" = "--provenance" ]; then
  want=$(conf CBQA_SIGNING_IDENTITY_HASH)
  # Branch mode needs the record, the matching version-build AND an Apple Development signature; a Developer ID
  # build routes to the release checks even when a stale record is left over (the record is ignored, not read).
  if [ ! -f "$record" ] || [ "$(vb "$app" 2>/dev/null)" != "$(rec VERSION_BUILD)" ] || ! apple_dev "$app"; then
    echo "mode=release"; exit 0
  fi
  have=$(signed_hash "$app")
  echo "mode=branch-candidate"; echo "version-build=$(rec VERSION_BUILD)"; echo "branch-sha=$(rec SHA)"
  echo "identity=$have"
  fail() { echo "provenance=FAIL $1"; exit 1; }
  valid_hash "$want" || fail "configured identity invalid"
  up() { printf '%s' "$1" | tr a-f A-F; }
  [ -n "$have" ] && [ "$(up "$have")" = "$(up "$want")" ] && [ "$(up "$have")" = "$(up "$(rec IDENTITY_HASH)")" ] \
    || fail "signing identity differs from the configured hash"
  codesign --verify --deep --strict "$app" 2>/dev/null || fail "codesign verify failed"
  echo "provenance=ok"; exit 0
fi

[ $# -eq 2 ] || { echo "usage: resign.sh <candidate.app> <branch-sha> | --provenance" >&2; exit 64; }
cand=$1; sha=$2
want=$(conf CBQA_SIGNING_IDENTITY_HASH)
valid_hash "$want" || { echo "BLOCKED qa-identity-invalid"; exit 4; }
# Fail closed on a locked login keychain (a plain ssh session) before any codesign call: codesign must never wait for a prompt.
keychain=${CBQA_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}
security show-keychain-info "$keychain" >/dev/null 2>&1 || { echo "BLOCKED keychain-locked: run from the lane's gui context"; exit 6; }
case $stage in */staged) ;; *) exit 64 ;; esac
rm -rf "$stage"; mkdir -p "$stage"
block() { echo "BLOCKED qa-signing-failed: $1"; rm -rf "$stage"; exit 3; }
ditto "$cand" "$stage/ContainerBar.app" || block "cannot stage the candidate"
xattr -dr com.apple.quarantine "$stage/ContainerBar.app" 2>/dev/null
want_id=com.tookes.ContainerBar   # the hunt build (.hunt) keeps its ad-hoc signature and is never re-signed
[ "$(plist_id "$cand")" = "$want_id" ] || block "bundle identifier is '$(plist_id "$cand")', expected $want_id"
args=(--force --deep --options runtime --sign "$want")
if [ -n "$(codesign -d --entitlements - "$cand" 2>/dev/null | head -c1)" ]; then
  [ -f "$ent" ] || block "entitlements copy missing from the workspace"
  args+=(--entitlements "$ent")
fi
err=$(codesign "${args[@]}" "$stage/ContainerBar.app" 2>&1) || block "$(printf '%s' "$err" | head -n1)"
err=$(codesign --verify --deep --strict "$stage/ContainerBar.app" 2>&1) || block "$(printf '%s' "$err" | head -n1)"
[ "$(plist_id "$stage/ContainerBar.app")" = "$want_id" ] && [ "$(signed_id "$stage/ContainerBar.app")" = "$want_id" ] \
  || block "signed bundle identifier is '$(signed_id "$stage/ContainerBar.app")', expected $want_id"
! xattr -lr "$stage/ContainerBar.app" 2>/dev/null | grep -q com.apple.quarantine || block "quarantine attribute still present"
want_up=$(printf '%s' "$want" | tr a-f A-F)
[ "$(signed_hash "$stage/ContainerBar.app")" = "$want_up" ] || block "signed with another identity"

# Hold the shared desktop lock and confirm CI idle before quitting or replacing anything (brief-template.md contract).
# case-gate checks that this pass owns the lock, the time budget and the CI-busy predicate; it never takes or removes the lock.
gate_blocked() { echo "BLOCKED $1"; rm -rf "$stage"; exit 7; }
if [ -z "${CBQA_LOCK_TOKEN:-}" ]; then gate_blocked "desktop-busy: lock-not-owned (no CBQA_LOCK_TOKEN)"; fi
if [ -n "${CBQA_LANE_CMD:-}" ]; then gate=$("$CBQA_LANE_CMD" case-gate --token "$CBQA_LOCK_TOKEN" 2>&1); grc=$?
else gate=$(python3 "$here/cbqa_lane.py" case-gate --token "$CBQA_LOCK_TOKEN" 2>&1); grc=$?; fi
if [ "$grc" -ne 0 ]; then
  case $gate in
    *ci-busy*) gate_blocked "ci-busy" ;;
    *) gate_blocked "desktop-busy: $(printf '%s' "$gate" | head -n1)" ;;
  esac
fi

# The installed app's PIDs, resolved from its bundle path (never by process name: the hunt build shares the executable name).
app_pids() { pgrep -f "^$(printf '%s' "$app/Contents/MacOS/" | sed 's/[][\.*^$+?(){}|]/\\&/g')" 2>/dev/null; }
# A running old binary must not be tested against the new provenance: quit it gracefully (never a signal).
if [ -n "$(app_pids)" ]; then
  osascript -e 'tell application id "com.tookes.ContainerBar" to quit' >/dev/null 2>&1
  for _ in $(seq 40); do [ -z "$(app_pids)" ] && break; sleep "${CBQA_QUIT_POLL:-0.5}"; done
  if [ -n "$(app_pids)" ]; then
    echo "BLOCKED app-quit-timeout: the installed ContainerBar refused to quit (a modal sheet may block it); nothing installed"
    rm -rf "$stage"; exit 5
  fi
  echo "relaunch required: ContainerBar was quit before the replace"
fi

# Replace without ever removing the installed app first: copy to a sibling temp bundle, verify it there, swap, verify in
# place, and only then drop the old bundle. Any failure restores the previous installation.
new=$app.cbqa-new.$$; old=$app.cbqa-old.$$; had_old=0; had_rec=0
install_failed() { echo "BLOCKED qa-install-failed: $1; the previous installation was kept"; rm -rf "$new" "$stage"; exit 8; }
rollback() {   # undo the swap: put the old bundle (if any) and the old record (if any) back
  rm -rf "$app" 2>/dev/null
  [ "$had_old" = 1 ] && mv "$old" "$app"
  if [ "$had_rec" = 1 ]; then cp -p "$stage/record.prev" "$record" 2>/dev/null; else rm -f "$record" 2>/dev/null; fi
}
verify_at() { codesign --verify --deep --strict "$1" >/dev/null 2>&1 && [ "$(signed_hash "$1")" = "$want_up" ]; }
rm -rf "$new"
ditto "$stage/ContainerBar.app" "$new" || install_failed "cannot copy the candidate next to the installed app"
verify_at "$new" || install_failed "the copied bundle failed verification"
[ -f "$record" ] && cp -p "$record" "$stage/record.prev" && had_rec=1
if [ -e "$app" ]; then
  mv "$app" "$old" || install_failed "cannot move the installed app aside"; had_old=1
fi
if ! mv "$new" "$app"; then rollback; install_failed "cannot move the new bundle into place"; fi
if ! verify_at "$app"; then rollback; install_failed "the installed bundle failed verification"; fi

# Provenance record: temp file + rename in the same directory, read back and compared before reporting success.
mkdir -p "$dir"
tmp=$(mktemp "$record.XXXXXX") && printf 'VERSION_BUILD=%s\nSHA=%s\nIDENTITY_HASH=%s\n' "$(vb "$app")" "$sha" "$want_up" > "$tmp" \
  && mv "$tmp" "$record" || { rm -f "$tmp" 2>/dev/null; rollback; install_failed "cannot write branch-candidate.env"; }
if [ "$(rec VERSION_BUILD)" != "$(vb "$app")" ] || [ "$(rec SHA)" != "$sha" ] || [ "$(rec IDENTITY_HASH)" != "$want_up" ] \
   || [ "$(signed_hash "$app")" != "$want_up" ]; then
  rollback; install_failed "branch-candidate.env does not match the installed bundle"
fi
rm -rf "$old" "$stage"
echo "installed $(vb "$app") signed by $want_up"
