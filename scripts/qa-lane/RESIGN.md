# Branch builds in the QA lane: re-sign and provenance (CB-124)

Companion to `CONTAINERBAR_QA.md` ("Branch builds"). Requirements: `docs/requirements/apple-signing-automation.md` (US-4).

## Why Apple Development, and why launchd only

- A branch or CI build is ad-hoc signed, so macOS treats every one as a new app and asks for Local Network again. Re-signing every
  branch build with one stable identity lets a single grant cover them all. The QA Mini holds an Apple Development identity
  (team 6739LM5834) in its login keychain; Developer ID stays reserved for releases.
- `codesign` can use that key only from the lane's launchd `gui/501` context. Over plain SSH the login keychain is locked and codesign
  fails with `errSecInternalComponent` (verified 2026-11-16). Never type a keychain password; run `resign.sh` from the launchd agent.
- `spctl` and `stapler` are NOT expected to pass: Apple Development is not notarized, and the Developer ID Authority match does
  not apply to a branch candidate (the provenance check replaces it).

## Configuration (private, in the workspace, never in the repo)

`qa/containerbar/lane.env` key `CBQA_SIGNING_IDENTITY_HASH=<SHA-1 of the active identity certificate>`. homelab-it sets it when the
identity is installed and moves it on renewal. `resign.sh` selects the identity by that hash and checks it is listed by
`security find-identity -v -p codesigning` first; a name match is never used (old and new identities coexist during renewal).
`install.sh` copies `Distribution/ContainerBar.entitlements` to `qa/containerbar/ContainerBar.entitlements`; `resign.sh` passes it only
when the candidate was built with entitlements.

## What `resign.sh` does

1. Validate the hash, else `BLOCKED qa-identity-invalid` (exit 4, nothing touched).
2. Copy the candidate to `artifacts/containerbar-qa/staged/`, sign it there, run `codesign --verify --deep --strict` and confirm the
   signing certificate's SHA-1 equals the configured hash. Any failure: `BLOCKED qa-signing-failed: <first stderr line>` (exit 3),
   the staged copy is removed and `/Applications/ContainerBar.app` is not changed.
3. Replace the installed app and write `qa/containerbar/branch-candidate.env` (`VERSION_BUILD`, `SHA`, `IDENTITY_HASH`).

## Provenance (TC-CB-01 for a branch candidate)

`resign.sh --provenance` prints `mode=release` unless the record exists and the installed version-build equals the recorded one.
For a branch candidate it checks the installed app's version-build (from its own Info.plist, recorded at install), that the signing
certificate hash equals the configured hash and the recorded one, and a clean `codesign --verify`. The tag = appcast = cask comparison
is skipped. Report the recorded branch sha in `report.md`.

## Local Network grant

The first run of a re-signed build shows the Local Network dialog once for this identity. Michael clicks Allow via Jump Desktop (the
lane never clicks it) and the lane appends `<YYYY-MM-DD> | apple-development | <identity SHA-1> | michael` to
`qa/containerbar/local-network-grants.log`. The grant names the signing identity, not the build, so a rebuild signed by the same
identity keeps the gate open. The Keychain "Always Allow" prompt also needs Michael once.

## Round 2 additions (Codex r2)

- Running app: `resign.sh` asks ContainerBar to quit (`osascript`, bounded wait, never a kill) before replacing the bundle and prints `relaunch required`; the lane must launch fresh, not reuse the old PID. If it will not quit: exit 5, `BLOCKED app-quit-timeout`, nothing installed (superseded by the install-path section below).
- `--provenance`: branch mode needs an Apple Development signature AND a record matching the installed version-build. A Developer ID signature is `mode=release` even with a stale record.
- Gate: a branch candidate (non-empty HASH) is opened only by an `apple-development` line with its hash; `developer-id` and `adhoc` lines do not open it.
- Hourly checks call `resign.sh --provenance`: a verified branch candidate skips spctl and release-drift; unverified gives `branch-provenance-failed`.
- `com.apple.quarantine` is stripped from the staged copy and verified absent before install.
- `CFBundleIdentifier` must be `com.tookes.ContainerBar` before and after signing, else `BLOCKED qa-signing-failed` naming the identifier (hunt builds are excluded).

## Install path (CB-133, Codex r3 on PR 81)

Order: identity hash, keychain check, stage and sign, lock and CI gate, quit, swap, record.

- Keychain: `security show-keychain-info` on the login keychain (`CBQA_KEYCHAIN` overrides) runs before the first `codesign`; locked gives `BLOCKED keychain-locked` (exit 6), nothing staged.
- Lock: the caller passes preflight's lock token in `CBQA_LOCK_TOKEN`; `resign.sh` runs `cbqa_lane.py case-gate --token` (lock owned, time budget, CI idle) before quitting. `BLOCKED desktop-busy` or `BLOCKED ci-busy` (exit 7), app untouched, no lock is taken or removed. No token counts as not owned.
- Quit: PIDs come from `pgrep -f` on `<installed app>/Contents/MacOS/`, so a running hunt build is neither waited on nor quit. Timeout: `BLOCKED app-quit-timeout` (exit 5). No signals are sent.
- Swap: `ditto` to `ContainerBar.app.cbqa-new.<pid>`, verify there, move the old bundle to `.cbqa-old.<pid>`, move the new one in, verify in place, delete the old one last. Any failure restores the old bundle and removes the temp: `BLOCKED qa-install-failed` (exit 8), "previous installation was kept".
- Record: `branch-candidate.env` is written to a temp file and renamed, then read back (version-build, sha, identity hash, signed hash). A failure rolls the bundle and the previous record back (or removes the new one) and never prints `installed`.
