# Requirements: unattended Apple Development signing for the ContainerBar QA lane

| | |
|---|---|
| Slug | `apple-signing-automation` |
| Status | Draft (business analyst, 2026-10-16). Awaiting the solution architect's feasibility review and technical tasks on this branch. No UX review: no story has a screen. |
| Backlog | CB-121 to CB-125 (High, directly after CB-116) |
| Parent | CB-116 option A (Apple-issued signing identity on the QA Mini so the Local Network grant persists across branch builds) |
| Owners | Michael (one-time setup only), vendor-ops (Apple API), homelab-it (QA Mini keychain), orchestrator (runbook, recipe, brief) |

This file is public (the repository is public). It names no host address, account user name, key id, issuer id, certificate serial, password, or private path on the Mini. Values like these live in `~/.config/genkei/vendors.env` on the MacBook or in the agent workspace on the Mini and are written here as `<placeholder>`.

## 1. Problem

The daily QA lane installs branch builds of ContainerBar on Lucius' Mac mini (the QA Mini). Those builds are signed ad hoc (`codesign --sign -`, `scripts/build-hunt-app.sh` line 122). macOS 15 and later keys the Local Network grant to the code-signing identity only for code signed with an Apple-issued identity; for ad-hoc code it falls back to the executable's UUID, which changes on every build (Apple TN3179, recorded in CB-116). So every branch build can raise "Allow "ContainerBar" to find devices on local networks?", and every SSH-transport case (TC-CB-03 to TC-CB-10, TC-CB-15 to TC-CB-17) is blocked until a person clicks Allow.

CB-116 chose option A: sign QA builds with an Apple Development certificate from Michael's developer account. Two steps of that still need Michael today, and the second repeats every year:

1. The private key must be created inside the Mini's unlocked desktop keychain. Over SSH the login keychain is locked, and a one-shot gui launchd job to do it unattended was refused by the permission classifier (homelab-it, 2026-10-16 11:08 CT). The scripted path (`~/work/cb116/csr.exp` on the Mini, `certtool` driven by `expect`) is verified against a throwaway keychain.
2. The certificate is issued by Michael's Apple Developer account, by hand in the portal.

How we know: Michael's answer on the CB-116 ask, 2026-10-16 10:58 CT: "Are you not able to run the commands to sign this? ... You should already have all the tools necessary to handle the signings." He asked the same day for "the ticket together for the API key that will be needed to fully automate the signing process". Agents have the tools for everything except the account credential and the first key creation in a desktop session.

What exists today and does not change: the release pipeline (`scripts/build-release.sh`, Developer ID Application identity on the MacBook, notarization profile `ContainerBar-Notarize`) is untouched by this work. The Developer ID key never moves to the QA Mini.

## 2. Goal and non-goals

**Goal.** After one setup session by Michael (about five minutes: one API key, three values, one Terminal command on the Mini), agents issue the QA Mini's Apple Development certificate through the App Store Connect API, install it, sign every QA branch build with it unattended, warn 30 days before it expires, renew it, and revoke it on demand, with no further action by Michael.

**How we know it worked.** (a) A branch build from a new commit, signed with the identity, connects to `QA Runtime` with no Local Network prompt after one grant (TC-CB-22). (b) The renewal a year from now completes without an inbox line addressed to Michael. (c) Zero secrets in any repo, brief, report, or Discord post (grep check in each story).

**Non-goals.**
- No change to release signing, notarization, the Homebrew cask, or Sparkle.
- No distribution certificates of any kind are created by this lane (Apple Distribution, Developer ID, installer). The API key could create some of them; the runbook refuses to.
- No provisioning profiles: a macOS app signed with Apple Development that uses no restricted entitlements runs without one. If the architect finds an entitlement in `Distribution/` that needs a profile, that is a new story, not an expansion of this one.
- No app code changes.

## 3. Users and roles

| Role | What they do here |
|---|---|
| Michael (Account Holder of the Apple developer team) | Once: creates the team API key, stores three values, runs the CSR command in a Jump Desktop session on the Mini, and clears at most one keychain prompt. Never again unless the API key is revoked or Apple requires a new agreement. |
| vendor-ops (MacBook) | Holds the API key through `vendors.env`; creates, lists, downloads and revokes certificates via the App Store Connect API; writes a redacted run report under `genkei-ops/docs/vendor-runs/`. |
| homelab-it (QA Mini over SSH) | Copies CSRs off the Mini, imports issued certificates, sets key access so `codesign` works unattended, runs the renewal key generation, removes revoked identities. |
| Lucius / the QA lane (QA Mini desktop session) | Re-signs each branch build with the identity, verifies the signature, reports BLOCKED states. Never types a password, never clicks a keychain or TCC dialog. |
| Orchestrator | Writes the Apple runbook and the recipe/brief changes, fires the yearly renewal, relays failures. |

## 4. Definitions

- **QA identity**: the Apple Development certificate plus its private key in a keychain on the QA Mini, common name `Apple Development: <account name> (<id>)`, team id `<team id>` (the same team as the release; the team id appears in `scripts/build-release.sh`).
- **Identity hash**: the SHA-1 of the certificate as printed by `security find-identity -v -p codesigning`; signing uses the hash, never the name, so an old and a renewed certificate with the same name are never ambiguous.
- **API key**: an App Store Connect **team** key. Individual keys cannot use provisioning endpoints, which include certificates (Apple, "Creating API Keys for App Store Connect API").
- **vendors.env**: `~/.config/genkei/vendors.env` on the MacBook, mode 600, outside every repo, never sourced (vendor-config skill rules).

## 5. Required Apple role, and why

**The API key needs the Admin role.** Source: Apple Developer Program roles table (developer.apple.com/help/account/access/roles, read 2026-10-16), rows "Submit certificate signing requests" and "Create and revoke development certificates": Account Holder and Admin have full access; App Manager and Developer have it only with "access to Certificates, Identifiers & Profiles, which can be provided in App Store Connect", a per-user permission in Users and Access. A team API key gets a role and nothing else (Apple, "Creating API Keys for App Store Connect API": "Under Access, select the role for the key"), so a Developer-role team key has no way to receive that permission and `POST /v1/certificates` answers 403 "Request not authorized". Admin also covers revocation (`DELETE /v1/certificates/{id}`), which renewal and the compromise path need. The `POST /v1/certificates` reference page itself states no role (it lists 201, 400, 401, 403, 409, 422, 429), which is why the role is taken from the program roles table. Only the Account Holder or an Admin can generate team keys. The earlier default in the CB-116 ask (Developer role) is corrected by this brief.

Risk that comes with Admin: an Admin key can also manage users and other certificates. Mitigations are in the constraints (section 7): the key lives only on the MacBook, every token is short-lived and scoped, the runbook exposes only the certificate commands it needs, and the key is revoked the day it is suspected lost.

Verify in the first run (US-apple-signing-automation-1 AC2): a scoped `GET /v1/certificates?filter[certificateType]=DEVELOPMENT` returns 200. If Apple's account type blocks team keys (Integrations shows "Request Access" instead of Team Keys), Michael clicks Request Access once and the setup waits for Apple's approval; see open question 1.

## 6. User stories and acceptance criteria

### US-apple-signing-automation-1: One-time API key setup (CB-121)

As Michael, I want to give the agents one App Store Connect API key in one place, so that I never have to issue or renew the QA signing certificate by hand again.

The ask, exactly as Michael receives it (self-contained, also in the inbox line):

1. App Store Connect > Users and Access > Integrations > App Store Connect API > Team Keys > Generate API Key (if the page shows Request Access instead, click it, then come back once Apple approves). Name: `Genkei QA signing`. Access: **Admin**. Default: Admin, because a Developer-role team key cannot create certificates.
2. Copy the **Key ID** (in the key's row), the **Issuer ID** (top of the same page), and click **Download API Key** for the `.p8` (Apple allows one download only). Default: save the file as `~/.config/genkei/AuthKey_<KEY ID>.p8` on the MacBook, then run `chmod 600 ~/.config/genkei/AuthKey_*.p8`.
3. Add three lines to `~/.config/genkei/vendors.env` on the MacBook: `APPSTORE_KEY_ID=<Key ID>`, `APPSTORE_ISSUER_ID=<Issuer ID>`, `APPSTORE_P8_PATH=/Users/<you>/.config/genkei/AuthKey_<KEY ID>.p8`. Default: those exact names; nothing pasted into chat, a repo, or Discord.
4. In a Jump Desktop session on Lucius' Mini, open Terminal and run `mkdir -p ~/Desktop && /usr/bin/expect ~/work/cb116/csr.exp ~/Library/Keychains/login.keychain-db ~/Desktop/ContainerBar-QA-Mini.certSigningRequest "Genkei Labs QA Mini (ContainerBar)" && chmod 600 ~/Desktop/ContainerBar-QA-Mini.certSigningRequest`, then tell the orchestrator "CSR ready". Default: do it now (about one minute); the alternative is approving a one-shot gui launchd job so homelab-it runs it unattended.
5. When the first signing shows a keychain prompt on the Mini's desktop, type the Mini's login password and click Always Allow. Default: once, only if it appears.

Acceptance criteria:
- AC1. Given the three lines are in `vendors.env`, when vendor-ops runs the Apple script's credential check, then it reports all three variables present, the `.p8` file exists with mode `-rw-------` (`stat -f %Sp`), and it prints no value of any of them. Given one is missing, then it exits 3 and prints the exact line to add (for example `APPSTORE_ISSUER_ID=<value>`), and nothing is sent to Apple.
- AC2. Given valid credentials, when vendor-ops runs the read-only check (`GET /v1/certificates?filter[certificateType]=DEVELOPMENT` with a token whose lifetime is at most 20 minutes and whose `scope` names only that request), then Apple answers 200 and the run report lists the count of development certificates and nothing else from the response.
- AC3 (unhappy, wrong role). Given the key was created with the Developer role, when vendor-ops runs the create dry-run followed by a real create, then the 403 is reported as "API key role cannot create certificates: generate a new team key with the Admin role and replace APPSTORE_KEY_ID and APPSTORE_P8_PATH", no retry is made, and the inbox line is `needs-decision`.
- AC4 (unhappy, key revoked or wrong issuer). Given the key was revoked in App Store Connect or the issuer id is wrong, when any call runs, then the 401 is reported as "App Store Connect key rejected (revoked, expired or wrong issuer id)", the run stops, and the inbox line asks Michael to repeat steps 1 to 3 only.
- AC5 (amended 2026-10-16, PR 77 review). Given the setup is done, when the check runs, then the credential leak check passes (amended again 2026-10-16, PR 77 review round 2). It has three parts, each quiet (`-q` or a count, never a mode that prints a matching line) and each run over the working tree and the full history (`git log -p --all`) of this repo and `genkei-ops`, and over every vendor-run report: (a) **real values, fixed strings** (`grep -qF -f` / `grep -cF -f`): `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID` and every base64 body line of the `.p8`, read by name on the MacBook and never printed, from a mode-600 pattern file deleted when the check ends; (b) **JWTs, a separate regex check** (`grep -qE` / `grep -cE`; `grep -F` cannot express it): three base64url segments separated by dots, the first starting `eyJ`, each segment at least 10 characters; (c) **key material, not marker text**: a PEM header line for a private key or a certificate request whose next line is a base64 body line of 40 or more characters (a two-line scan that returns a count). Paths that hold known parser literals are excluded from (c) by path through an allowlist in the check, starting with `Sources/ContainerBarCore/API/TLSCertificateLoader.swift`; (a) and (b) have no exclusions. Tests, all required: on a clean checkout of both repos the check exits 0 (so the `TLSCertificateLoader.swift` literals, in the tree and in history, and this brief's own prose do not trip it); with a planted fixed value, a planted synthetic JWT, and a planted synthetic PEM key block (generated for the test, never a real key) in scratch files, each run exits non-zero. Failure output names only the file and line number (for history, the commit and file), never the value or the line.

### US-apple-signing-automation-2: Apple runbook in vendor-ops issues, downloads and revokes development certificates (CB-122)

As the orchestrator, I want an Apple runbook in the vendor-config skill that turns a CSR into an Apple Development certificate through the API, so that issuance and renewal are one command with a dry-run and a run report, like every other vendor.

What the orchestrator writes (genkei-ops side, in `~/.claude/skills/vendor-config/`; described here, not written by this brief):
- `runbooks/apple.md`: tasks table in the existing format (Task | How | API-able? | Verify | Rollback) for `cert-list`, `cert-create-dev <csr path>`, `cert-download <id> <out.cer>`, `cert-revoke <id>`; credentials `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_P8_PATH`; a **Never** line: never create `DISTRIBUTION`, `DEVELOPER_ID_*`, `MAC_*`, `IOS_*`, Apple Pay or pass certificates, never touch users, never revoke a certificate this lane did not create.
- `scripts/apple.sh` on top of `lib.sh`: loads the three variables without sourcing; signs an ES256 JWT (`alg` ES256, `kid` key id, `typ` JWT; payload `iss` issuer id, `iat`, `exp` at most 20 minutes later, `aud` `appstoreconnect-v1`, `scope` set to the one request) with the `.p8`; every mutation takes `--dry-run` and prints the request with the CSR body elided; responses pass through `redact`.
- Create: `POST https://api.appstoreconnect.apple.com/v1/certificates` with `data.type = "certificates"`, `attributes.certificateType = "DEVELOPMENT"` (Apple Development, the cross-platform development type), `attributes.csrContent` = the complete PEM text of the CSR file, BEGIN and END marker lines and newlines included, JSON-escaped (built with a JSON encoder such as `jq --rawfile`, never by string concatenation); this matches Apple's certificate creation example, which sends PEM, not the base64 body alone (amended 2026-10-16, PR 77 review). The response's `certificateContent` (base64 DER) is written to a `.cer` file mode 600; `id`, `serialNumber`, `expirationDate` and `name` go to the run report (the serial and id are fine in genkei-ops, never in this public repo).
- Production gate: the Apple account has no sandbox, so every mutation is production. The standing work order for this lane ("production approved" for `cert-create-dev` and `cert-revoke` of lane-created certificates only) is recorded once in `genkei-ops/docs/decisions.md` when Michael answers; anything else in the account waits for Michael.
- Hand-off: the `.cer` is copied to the QA Mini by homelab-it (`scp` into the lane's work directory), then deleted from the MacBook after US-3 AC2 passes.

Acceptance criteria:
- AC1. Given a CSR file, when `apple.sh cert-create-dev <csr> --dry-run` runs, then it prints `POST /v1/certificates` with `certificateType DEVELOPMENT` and `csrContent <elided PEM, N bytes, BEGIN/END markers present>` (the script checks the first line is the PEM certificate-request header and the last its END line, and refuses with exit 6 otherwise), sends nothing (no network call in the run log), and exits 0.
- AC2. Given the same CSR and the standing approval, when it runs without `--dry-run`, then Apple returns 201, a `.cer` file exists with mode 600, `openssl x509 -inform der -noout -subject -enddate` on it shows a subject starting `Apple Development:` and an end date about one year out, and a follow-up `cert-list` (a read, not the create response) shows the new id.
- AC3. Given a request for any other certificate type (for example `DEVELOPER_ID_APPLICATION`), when the script is called, then it refuses with exit 5 and sends nothing.
- AC4 (unhappy, rate limit). Given Apple answers 429 `RATE_LIMIT_EXCEEDED`, then the script logs the `X-Rate-Limit` header (`user-hour-lim`, `user-hour-rem`), makes no further call for 60 minutes, retries once, and on a second 429 stops with the inbox line `blocked` and reason `apple-rate-limit`. No loop retries.
- AC5 (unhappy, CSR rejected or certificate cap). Given Apple answers 409 or 422 (invalid CSR, or the team's development certificate limit reached), then the script prints Apple's `errors[].detail` verbatim, revokes nothing on its own, and the run report lists the lane-created development certificates with their expiry so the orchestrator can choose one to revoke under US-5.
- AC6. Given the run finished, then a run report exists under `genkei-ops/docs/vendor-runs/` with what changed, the redacted request and response, the read-back, the rollback (`apple.sh cert-revoke <id>`), and the inbox line, and the US-1 AC5 leak check over it (quiet, working tree and history, file and line only on failure) finds no key id, issuer id, `.p8` line, JWT, CSR or certificate body.

### US-apple-signing-automation-3: QA Mini signing identity installed and usable unattended (CB-123)

As the QA lane, I want the Apple Development identity in a keychain on the QA Mini that `codesign` can use without a prompt, so that branch builds are signed by the lane with no person at the desktop.

Acceptance criteria:
- AC1. Given Michael ran ask step 4, when homelab-it checks over SSH, then `~/Desktop/ContainerBar-QA-Mini.certSigningRequest` exists with mode 600, `openssl req -noout -verify -in` on it reports `verify OK`, the subject CN is `Genkei Labs QA Mini (ContainerBar)`, and the CSR is copied to the MacBook only into the vendor-ops work directory (never a repo) and deleted from the Mini's Desktop after US-2 AC2 passes.
- AC2. Given the issued `.cer` was copied to the Mini, when homelab-it imports it into the same keychain that holds the private key (`security import <file>.cer -k <keychain>`), then the SHA-1 of the issued certificate (computed from the `.cer`, `openssl x509 -inform der -noout -fingerprint -sha1`) appears as a valid identity in `security find-identity -v -p codesigning`, and that hash is recorded in the lane's workspace config (not in this repo). The check selects by that hash and never counts identities: during renewal (US-5) the old and the new Apple Development identities are both valid by design, and the old one stays until the new one is validated (amended 2026-10-16, PR 77 review).
- AC3. Given the identity is installed, when a test bundle is signed by the context the QA lane uses (the gui launchd domain of the Mini's desktop user, the same domain CB-105's agent runs in), then `codesign --force --sign <identity hash>` exits 0 with no dialog on the desktop. If a keychain dialog appears on the first use, ask step 5 clears it once; the second signing shows none.
- AC4. Given the same check run from an SSH session, then either it succeeds (the architect chose a keychain the lane can unlock non-interactively, see open question 2) or it fails with `errSecInternalComponent` and the lane's design records that signing runs only in the gui domain. Either result is written down; neither is silent.
- AC5 (unhappy, keychain locked; amended 2026-10-16, PR 77 review). Given the keychain holding the key is locked, as reported by an actual lock-state query run in the signing context immediately before every signing attempt (`SecKeychainGetStatus` read for `kSecUnlockStateStatus`, or a scripted equivalent the architect names). The query fails closed: only an explicit unlocked status allows signing; an error, a missing keychain or an unknown result counts as locked. `security show-keychain-info` is not used for this: it reports the timeout and lock-on-sleep settings, not the lock state, when signing would be attempted, then the lane does not prompt, does not type a password, ends `BLOCKED keychain-locked`, and posts one line to `#lucius-updates`.
- AC6 (amended 2026-10-16, PR 77 review round 2). Given the private key, then it never leaves the Mini: no `.p12` export exists: before the CSR is deleted, homelab-it writes a timestamp marker file in the lane's work directory (mode 600, kept until the check has run on both machines; the CSR is not the reference because AC1 deletes it), then runs `find ~ -name '*.p12' -newer <marker>` on the Mini and on the MacBook. The check passes only if `find` exits 0 **and** prints nothing; a non-zero exit (missing marker, unreadable directory) is a failure, not a pass, and empty output alone never counts; and `git log -p` over this repo shows no certificate, key or CSR.

### US-apple-signing-automation-4: The daily QA lane signs branch builds with the QA identity and the grant survives a rebuild (CB-124)

As the QA lane, I want every branch build I install re-signed with the QA identity and checked before I run any case, so that one Local Network grant covers all branch builds and a bad signature is caught before it looks like a product failure.

Acceptance criteria:
Which build each criterion applies to (amended 2026-10-16, PR 77 review): AC1 to AC7 apply to the **normal branch build** (bundle identifier `com.tookes.ContainerBar`, real transports), the build the desktop checks and the QA Runtime cases (TC-CB-03, TC-CB-05) install; AC5 also covers the released build. The **hunt-mode build** from `scripts/build-hunt-app.sh` (bundle identifier `com.tookes.ContainerBar.hunt`, `FixtureDockerAPIClient`, no real hosts, so no Local Network use) is excluded from every criterion here: it keeps its ad-hoc signature and its own Prowl path, and the lane never re-signs it with the QA identity.

- AC1. Given a normal branch build `ContainerBar.app` (bundle identifier `com.tookes.ContainerBar`, ad-hoc signed by the desktop-check build step), when the lane installs it, then it re-signs nested code first and the app last with `codesign --force --sign <identity hash> --identifier com.tookes.ContainerBar` (the architect fixes the exact flags and the nested-code order, see open question 3), and `codesign --verify --deep --strict` on the app exits 0.
- AC2. Given the re-signed app, when the lane runs `codesign -dv --verbose=4`, then the output contains `Authority=Apple Development:`, `Authority=Apple Worldwide Developer Relations Certification Authority`, `Authority=Apple Root CA`, `TeamIdentifier=<team id>` and `Identifier=com.tookes.ContainerBar`, and does not contain `Signature=adhoc`.
- AC3. Given the re-signed app, when the lane runs `spctl --assess --type execute -vv`, then it reports `rejected` with `origin=Apple Development: ...` (an Apple Development app is not notarized; Gatekeeper rejection is expected and is recorded, not treated as a failure), and the lane launches the app from a path without the quarantine attribute (`xattr -p com.apple.quarantine` reports no such attribute).
- AC4 (TC-CB-22). Given Michael granted Local Network once to a build signed with the QA identity, when a branch build from a different commit is re-signed with the same identity and installed, and TC-CB-05 Test Connection runs on `QA Runtime`, then it reports success and no Local Network prompt appears. The recipe records the grant (date, identity name, who granted).
- AC5. Given the released build (Developer ID) and a QA-signed branch build both run on the Mini on the same day, when the released build's daily TC-CB-03 runs after a branch-build run, then it still connects with no prompt. If this fails (the two identities replace each other's grant under one bundle identifier), the lane switches branch builds to the fixed QA bundle identifier the architect names and this AC is re-run.
- AC6 (unhappy, signing failed). Given `codesign` fails or AC2's checks do not all hold, then the lane installs nothing, ends `BLOCKED qa-signing-failed` with the first line of `codesign` stderr, marks no TC case FAIL, and posts one line to `#lucius-updates`.
- AC7 (unhappy, identity missing, expired or revoked). Given `security find-identity -v -p codesigning` lists no valid identity with the recorded hash (expired certificates and those whose revocation the system has seen drop out of the `-v` list), when preflight runs, then the pass ends `BLOCKED qa-identity-invalid` before installing the build, posts one line, and the orchestrator starts US-5 renewal. The released-build cases still run.

### US-apple-signing-automation-5: Renewal before expiry and revocation (CB-125)

As the orchestrator, I want the QA identity renewed before it expires and revocable in one command, so that the lane never stops on an expired certificate and a lost key is shut off the same day.

Acceptance criteria:
- AC1. Given the QA identity expires in 30 days or fewer (expiry read from the certificate whose SHA-1 equals the **active** hash recorded in the lane workspace: export every matching certificate with `security find-certificate -a -c "Apple Development" -p`, compute each one's SHA-1 with `openssl x509 -noout -fingerprint -sha1`, read `-enddate` only from the one that matches; `find-certificate` without `-a` returns the first name match, which during the renewal window can be the wrong certificate. If no certificate matches the active hash, the check reports `qa-identity-invalid` instead of an expiry; amended 2026-10-16, PR 77 review round 2), when CB-105's hourly check runs, then it emits one `needs-renewal` line per day (not per hour) to the orchestrator's inbox with the expiry date, and the daily pass continues.
- AC2. Given a renewal is due, when the orchestrator runs it, then a new key and CSR are created on the Mini by the unattended path the architect chose (see open question 2), vendor-ops issues the new certificate (US-2), homelab-it imports it next to the old one (US-3; both are valid identities during this window, the lane keeps signing with the old recorded hash), the new hash is recorded as `pending`, and TC-CB-22 runs once on a build signed with the new hash. Only when that and AC3 pass does the lane switch its active hash to the new identity (amended 2026-10-16, PR 77 review). No step addresses Michael. If the architect keeps the login keychain and no unattended key creation is possible, the fallback is ask step 4 once a year and this AC records that renewal is not yet unattended.
- AC3. Given the new identity carries the same common name and team, when the first branch build signed with it runs TC-CB-05, then it connects with no Local Network prompt (proposed TC-CB-24; the designated requirement of an Apple Development signature matches on team and common name, so the grant is expected to carry over; if a prompt appears, the recipe records a one-time grant per renewal).
- AC4. Given the renewal passed AC3 and the active hash was switched, then, and not before, the old certificate is revoked with `apple.sh cert-revoke <old id>`, removed from the keychain, and `cert-list` no longer shows it as valid.
- AC5 (compromise or Mini rebuild). Given the orchestrator or Michael says the QA identity is compromised, or the Mini is wiped, when `apple.sh cert-revoke <id>` runs, then Apple answers 204, `cert-list` no longer shows it, homelab-it deletes the identity from the keychain, the lane ends `BLOCKED qa-identity-invalid` until a new identity is issued (US-2, US-3), and the release pipeline is unaffected (the Developer ID identity is a different certificate).
- AC6 (unhappy, renewal fails). Given any renewal step fails (401, 403, 409, 429, keychain locked), then the old certificate is not revoked, the lane keeps signing with it until it expires, and the inbox line names the failed step and the expiry date.

## 7. Constraints

- **Secrets.** The `.p8`, JWTs, CSRs, `.cer` files, the private key and the Mini's login password never appear in this repo, `genkei-ops`, a brief, a report, Discord, or chat. `.p8` and `.cer` files are mode 600. The key and certificate ids and serials may appear in `genkei-ops/docs/vendor-runs/`, never in this public repo.
- **Token hygiene.** Every JWT lives at most 20 minutes and carries a `scope` naming its one request; tokens are generated per run and never written to disk.
- **Least use of an Admin key.** `apple.sh` exposes only the four certificate commands; there is no generic "call any endpoint" mode.
- **Rate limits.** Apple limits requests per key per rolling hour (`X-Rate-Limit: user-hour-lim:<n>;user-hour-rem:<m>;`, HTTP 429 `RATE_LIMIT_EXCEEDED`). This lane makes a handful of calls a year; any loop that could exceed that is a defect.
- **Kill ban and test machines.** No step stops a process on the MacBook or Michael's Mac mini. Signing and checks run on the QA Mini only.
- **Lucius never grants.** The CB-116 exception stands: only Michael clicks Allow on the ContainerBar Local Network dialog, and only Michael types the Mini's login password (ask step 5).
- **Platform.** macOS 15 or later on the QA Mini (TN3179 behaviour); Apple Silicon only, like the app.

## 8. Data and privacy notes

- Leaves the MacBook: the CSR (public key and the CN `Genkei Labs QA Mini (ContainerBar)`) and the signed JWT, to `api.appstoreconnect.apple.com` only.
- Leaves the QA Mini: the CSR, copied to the MacBook by homelab-it. The private key never leaves.
- Stored: the API key on the MacBook (`~/.config/genkei/`), the identity in a keychain on the QA Mini, the identity hash in the lane workspace, run reports in `genkei-ops/docs/vendor-runs/`.
- No end-user data, no consent copy, no change to what the app sends.

## 9. Open questions (with the assumption taken)

1. **For Michael: does the account offer Team Keys?** The release identity is issued to a person's name, which suggests an individual membership. Apple's help says the Account Holder must request API access first. Assumption: Team Keys are available after one Request Access click (ask step 1 covers it). If Apple does not offer team keys for this membership, the fallback is the portal path once a year (upload the CSR at developer.apple.com > Certificates > + > Apple Development, download the `.cer`), and CB-122 is parked.
2. **For the architect: which keychain holds the QA key?** The login keychain needs a desktop session to create keys (today's blocker) and is locked over SSH. A dedicated signing keychain whose password sits in a mode-600 file on the Mini (CB-116's option C) would let homelab-it create keys, import certificates, set the key partition list (`security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <password>`) and renew over SSH with no person at all, at the cost of a password on disk. Assumption: the first identity uses the login keychain (ask step 4, already scripted and verified); the architect decides whether renewal moves to a dedicated keychain, and if it does, Michael approves that one design change through the orchestrator.
3. **For the architect: nested code and bundle identifier.** Re-signing order for Sparkle's nested helpers, whether hardened runtime or entitlements are kept, and whether QA builds keep `com.tookes.ContainerBar` or use one fixed QA identifier (US-4 AC5 decides it by test). Assumption: keep `com.tookes.ContainerBar` as CB-116 says.
4. **For Michael (folded into the ask): the standing approval.** Assumption: answering the ask approves `cert-create-dev` and `cert-revoke` of lane-created development certificates without a per-run "production approved"; nothing else in the Apple account.

## 10. Out of scope

- Release signing, notarization, Developer ID renewal, and any move of the Developer ID key.
- Provisioning profiles, App IDs, capabilities, devices.
- Signing for other Genkei apps (Sentwise, Prompter); the runbook is reusable, and each app files its own story.
- Automating the Local Network Allow click.

## 11. Traceability

| Story | Backlog | Test case |
|---|---|---|
| US-apple-signing-automation-1 | CB-121 | proposed TC-CB-23 "QA signing credentials and identity valid" (preflight, daily) |
| US-apple-signing-automation-2 | CB-122 | vendor-run report read-back (no TC; account operation) |
| US-apple-signing-automation-3 | CB-123 | TC-CB-23 |
| US-apple-signing-automation-4 | CB-124 | TC-CB-22 (proposed in CB-116), TC-CB-05 precondition, TC-CB-03 |
| US-apple-signing-automation-5 | CB-125 | proposed TC-CB-24 "Local Network grant survives certificate renewal" (once per renewal) |

Sources (read 2026-10-16): Apple, "Creating API Keys for App Store Connect API"; "Generating Tokens for API Requests"; "Identifying Rate Limits"; "Create a certificate" (`POST /v1/certificates`); `CertificateType`; Apple Developer Program roles (developer.apple.com/help/account/access/roles); TN3179 "Understanding local network privacy" (via CB-116).
