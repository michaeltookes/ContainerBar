#!/bin/bash
# Re-sign a branch build with the QA Apple Development identity and check its provenance (CB-124).
#   resign.sh <candidate.app> <branch-sha>   stage, sign, verify, then replace the installed app
#   resign.sh --provenance                   print key=value lines, last one provenance=ok|FAIL <why>
# Exit codes: 0 ok, 1 provenance FAIL, 3 BLOCKED qa-signing-failed, 4 BLOCKED qa-identity-invalid, 64 usage.
# The identity is selected by SHA-1 hash from CBQA_SIGNING_IDENTITY_HASH in $WS/qa/containerbar/lane.env
# (homelab-it sets it; the value never enters the repo). Run only from the lane's launchd (gui) context.
set -u
ws=${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}
dir=$ws/qa/containerbar
app=${CBQA_APP_PATH:-/Applications/ContainerBar.app}
stage=$ws/artifacts/containerbar-qa/staged
record=$dir/branch-candidate.env
ent=$dir/ContainerBar.entitlements

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
valid_hash() {
  [[ $1 =~ ^[0-9A-Fa-f]{40}$ ]] && security find-identity -v -p codesigning 2>/dev/null | grep -qi "$1"
}

if [ "${1:-}" = "--provenance" ]; then
  want=$(conf CBQA_SIGNING_IDENTITY_HASH)
  if [ ! -f "$record" ] || [ "$(vb "$app" 2>/dev/null)" != "$(rec VERSION_BUILD)" ]; then
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
case $stage in */staged) ;; *) exit 64 ;; esac
rm -rf "$stage"; mkdir -p "$stage"
block() { echo "BLOCKED qa-signing-failed: $1"; rm -rf "$stage"; exit 3; }
ditto "$cand" "$stage/ContainerBar.app" || block "cannot stage the candidate"
args=(--force --deep --options runtime --sign "$want")
if [ -n "$(codesign -d --entitlements - "$cand" 2>/dev/null | head -c1)" ]; then
  [ -f "$ent" ] || block "entitlements copy missing from the workspace"
  args+=(--entitlements "$ent")
fi
err=$(codesign "${args[@]}" "$stage/ContainerBar.app" 2>&1) || block "$(printf '%s' "$err" | head -n1)"
err=$(codesign --verify --deep --strict "$stage/ContainerBar.app" 2>&1) || block "$(printf '%s' "$err" | head -n1)"
[ "$(signed_hash "$stage/ContainerBar.app")" = "$(printf '%s' "$want" | tr a-f A-F)" ] || block "signed with another identity"
# Only now touch the installed app.
rm -rf "$app" && ditto "$stage/ContainerBar.app" "$app" || block "cannot replace the installed app"
mkdir -p "$dir"
printf 'VERSION_BUILD=%s\nSHA=%s\nIDENTITY_HASH=%s\n' "$(vb "$app")" "$sha" "$(printf '%s' "$want" | tr a-f A-F)" > "$record"
rm -rf "$stage"
echo "installed $(vb "$app") signed by $(printf '%s' "$want" | tr a-f A-F)"
