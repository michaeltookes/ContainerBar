# Requirements: ContainerBar QA-lane leftovers

| | |
|---|---|
| Slug | `qa-lane-leftovers` |
| Status | Ready for architecture and project-planner review (business analyst, 2026-10-23) |
| Anchor | CB-126 |
| Backlog | CB-124, CB-126 to CB-131 |
| Source | QA-lane installation findings, 2026-10-22 to 2026-10-23 |
| Owners | Orchestrator (lane and workspace), builder (repo tooling/docs), homelab-it (QA Mini signing), Michael (one keychain prompt only) |

This public document uses placeholders for private paths, certificate names, hosts, and Discord destinations. It contains no credential value, private endpoint, or QA-host address.

## Problem

The CB-105 lane is now installed on the QA Mac: the hourly check is green against ContainerBar 2.0.4 installed from the Homebrew cask, and webhook delivery reaches the ContainerBar channel. An Apple Development identity was also imported on 2026-10-22. The install exposed four remaining groups of work:

1. **The operator instructions do not match the installed environment.** An SSH-launched shell may not include `/opt/homebrew/bin`, so `openclaw` is reported missing; a manual preflight legitimately holds the shared desktop lock until that invocation exits; and the recipe describes `CBQA_DEVELOPER_ID_AUTHORITY` as a Developer ID value even though the lane temporarily matches the imported Apple Development authority until a Developer ID-signed build is selected.
2. **A non-fixture container was observed on the dedicated QA runtime.** The current ticket calls this a `scope-breach`, but the operator needs an explicit decision between ignoring containers the lane did not create and refusing to run. The existing isolation contract says the runtime contains only `cbqa-` fixtures, so ignoring the container would conceal a failed safety precondition.
3. **Four review findings remain open.** The hourly path still needs a hard wall-clock bound (CB-126), “not observed” semantics for probes cut short by the budget (CB-127), durable undelivered failure snapshots (CB-128), and lock-token checks around every mutating lane command (CB-129).
4. **SSH product cases are still blocked.** Importing the identity did not itself create a ContainerBar build signed by that identity, authorize unattended key use, or establish a Local Network grant. Until one normal ContainerBar build is signed and installed, the one-time Keychain **Always Allow** prompt is answered, Test Connection is granted Local Network access, and `local-network-grants.log` records the successful identity/build, the SSH-dependent cases must stay BLOCKED rather than becoming false product failures.

How we know: the 2026-10-22 install and preflight observations in the work order, the open CB-126 to CB-130 tickets, and the existing contracts in `scripts/qa-lane/README.md`, `scripts/qa-lane/CONTAINERBAR_QA.md`, `docs/requirements/lucius-daily-qa.md`, and `docs/requirements/apple-signing-automation.md`.

## Goal and non-goals

**Goal.** Make the installed lane safe and operable without tribal knowledge, activate the imported Apple Development identity so SSH cases can run, and close the four hourly/lock reliability gaps without changing the lane's isolation, reporting, or time budgets.

**Success is observable when:**

- an SSH operator can run install/preflight commands without manually repairing PATH;
- a second preflight reports the existing lock rather than suggesting it is stale while the first invocation still runs;
- the expected authority configuration and actual app signature agree;
- a non-`cbqa-` container causes a pre-launch `scope-breach` refusal;
- a signed normal build can complete Test Connection with no Keychain prompt after the one-time setup, and a matching grant-log entry exists; and
- the hourly wrapper always preserves its state and pending alert within 55 seconds, including timeout and webhook-failure paths.

**Non-goals.**

- No ContainerBar product feature or user-facing UI change.
- No Developer ID private key on the QA Mac and no change to release signing, notarization, Sparkle, or the cask.
- No attempt to adopt, inspect, stop, rename, or delete a non-fixture container. The lane refuses to run; an authorized operator resolves the runtime breach outside this work.
- No automated click or password entry for Keychain or Local Network prompts.
- No change to the six-fixture baseline, daily schedule, 40-second hourly check budget, 8-second webhook allowance, or 55-second wrapper limit.

## Users and roles

| Role | Need and responsibility |
|---|---|
| Lucius / scheduled QA lane | Receives deterministic PASS, FAIL, or BLOCKED outcomes and never acts outside the dedicated fixtures. |
| Orchestrator | Installs the lane, runs manual preflights, creates the signed-build setup pass, records the Local Network grant, and relays findings. |
| Builder | Updates the versioned QA-lane docs/tooling for CB-124 and CB-126 to CB-131. |
| homelab-it | Confirms the imported identity is valid and available in the signing context without exposing its hash or key material. |
| Michael | Answers the one-time Keychain prompt by choosing Always Allow if it appears; agents never type the password. |
| Project manager | Confirms the build order proposed below. |

## User stories

### US-qa-lane-leftovers-1: Instructions match SSH, lock, and signing reality

As an orchestrator operating the QA lane over SSH, I want the documented environment, lock lifetime, and authority examples to match the installed lane, so that a correct setup is not mistaken for a broken one.

Backlog: **CB-131**.

- **AC1 — SSH PATH.** Given a non-interactive SSH shell whose incoming PATH omits `/opt/homebrew/bin`, when an operator follows the documented install, preflight, or OpenClaw command, then the command resolves `openclaw` by using an explicit known path or a documented PATH prefix that includes `/opt/homebrew/bin`; no instruction depends on an interactive shell profile.
- **AC2 — missing executable.** Given neither the explicit OpenClaw path nor `command -v openclaw` resolves an executable, when the preflight instruction runs, then it stops before acquiring the desktop lock and prints one actionable error naming the required executable location; it does not report a QA product failure.
- **AC3 — manual lock lifetime.** Given manual preflight A returned `READY` and its invocation has not run `release`, when preflight B starts, then B reports BLOCKED `desktop-busy`; the docs say A owns the lock until its restore/release sequence or outer deadline, rather than telling the operator to remove the lock.
- **AC4 — authority value.** Given the installed app is signed with Apple Development, when the static signature check compares the first `Authority=` line, then the configured expected value is the exact Apple Development authority line and the docs label the setting as the **expected codesign authority**, not specifically Developer ID. Given a Developer ID-signed cask is selected later, the same setting can hold the Developer ID authority without a code change.
- **AC5 — authority mismatch.** Given the configured authority and the installed app's first `Authority=` line differ, when static checks run, then the lane launches nothing, reports `authority-mismatch`, and does not acquire or remove the desktop lock.

### US-qa-lane-leftovers-2: Activate the imported Apple Development identity

As the QA lane, I want one normal ContainerBar build signed and authorized with the imported Apple Development identity, so that SSH-dependent cases can run without a prompt on every pass.

Backlog: **CB-124** (revised activation step; CB-116 and CB-121 setup is closed).

- **AC1 — signed build exists.** Given the imported active identity and a normal non-hunt ContainerBar build, when the setup signs and verifies the app, then `codesign --verify --deep --strict` exits 0; the first authority starts `Authority=Apple Development:`; the identifier is the lane's fixed normal-build identifier; and no identity hash, certificate body, key path, or password enters a report or repository.
- **AC2 — one-time Keychain authorization.** Given first use raises a Keychain access prompt, when Michael enters the QA Mac password and chooses **Always Allow**, then a second signing in the lane's GUI context exits 0 without a prompt. If nobody authorized to answer is present, the setup stops BLOCKED `keychain-authorization-required`; the agent does not type or dismiss anything.
- **AC3 — Local Network grant.** Given the verified signed build is installed and the shell-level `ssh cbqa-ctl status` succeeds, when Michael grants ContainerBar Local Network access once and the operator runs Settings > Connections > QA Runtime > Test Connection, then Test Connection reports success and no Local Network prompt remains open.
- **AC4 — durable evidence.** Given AC3 succeeds, when setup completes, then `local-network-grants.log` gains exactly one non-secret line in its defined format for the identity/build and actor, and a subsequent pass opens the gate from that line plus a successful Test Connection.
- **AC5 — missing setup evidence.** Given signing succeeded but the Keychain prompt remains unresolved, Test Connection did not succeed, or the grant-log line is absent, when an SSH-dependent case is reached, then it is BLOCKED with the specific setup reason and no product case is marked FAIL.
- **AC6 — rebuild persistence.** Given a second normal build from a different commit signed with the same identity and fixed identifier, when TC-CB-22 and TC-CB-05 run, then Test Connection succeeds without another Keychain or Local Network prompt. A new prompt keeps CB-124 open and the report records only the prompt type, never sensitive contents.

### US-qa-lane-leftovers-3: Refuse a contaminated QA runtime

As the owner, I want the lane to refuse to run when the dedicated runtime contains any non-fixture container, so that unattended QA never hides or normalizes a broken isolation boundary.

Backlog: **CB-130**. Decision: **preflight refuses; the lane does not ignore the container**.

- **AC1 — daily refusal.** Given `cbqa-ctl status` lists the six fixtures plus `example-service`, when the daily pass begins, then it reports FAIL `scope-breach`, names `example-service`, launches or relaunches no ContainerBar process, and runs no case.
- **AC2 — hourly classification.** Given the same status in an hourly run, when the fixture check runs, then it reports `scope-breach`, not `fixture-drift` or `qa-runtime-down`, and the alert names `example-service`.
- **AC3 — no mutation.** Given a scope breach, when either path exits, then it does not call reset in a way that removes the non-fixture, and it does not stop, inspect, rename, or delete that container; remediation belongs to an authorized runtime operator.
- **AC4 — unhappy combination.** Given a non-fixture container and one wrong-state `cbqa-` fixture are both present, when either path classifies status, then `scope-breach` wins and the lane still performs no app launch or product case.
- **AC5 — ordinary fixture drift.** Given every container name starts with `cbqa-` but the six-fixture names or states differ, when status is classified, then the daily path keeps its existing `qa-runtime-down` retry/block behavior and the hourly path keeps its existing `fixture-drift` behavior.

### US-qa-lane-leftovers-4: Hard wall-clock bounds around network calls

As the operator, I want release fetches and webhook delivery bounded by elapsed time, so that a slow DNS lookup or response body cannot prevent the hourly state from being saved.

Backlog: **CB-126**.

- **AC1 — slow body.** Given a fake release endpoint accepts a connection and sends one byte per second, when the release check runs, then the call returns or is abandoned within its remaining share of the 40-second check budget, that source is `not observed`, and the wrapper writes state and exits within 55 seconds.
- **AC2 — resolver stall.** Given an injected DNS resolution delay exceeds the remaining check budget, when a fetch starts, then it is abandoned at the hard deadline and the release result keeps its previous observed value.
- **AC3 — webhook stall.** Given the webhook accepts a connection but never responds, when an alert is posted, then the attempt ends within 8 seconds, the exact pending alert remains in state for the next run, and the wrapper exits within 55 seconds.
- **AC4 — successful calls.** Given all endpoints answer inside their bounds, when the check runs, then release comparison and posting retain their current behavior and no timeout warning appears.

### US-qa-lane-leftovers-5: Budget exhaustion means not observed

As the owner, I want a probe cut short by the shared budget to retain its last observation, so that elapsed time does not generate a false outage and recovery.

Backlog: **CB-127**.

- **AC1 — Gatekeeper timeout.** Given Gatekeeper was previously healthy and `spctl` exits 124 because the shared deadline is reached, when the result is classified, then no `gatekeeper-rejected` failure is added, the previous Gatekeeper value remains, and the log says `not observed (out of time)`.
- **AC2 — app timeout.** Given the app check's `pgrep` or `ps` is cut short at the deadline, when classified, then no `app-not-running` or resource failure is synthesized and the previous app result remains.
- **AC3 — runtime timeout.** Given `cbqa-ctl status` is cut short at the deadline, when classified, then no `qa-runtime-down` is synthesized and the previous runtime result remains.
- **AC4 — real failure.** Given any probe exits non-zero before its deadline with time remaining, when classified, then its existing real-failure result is reported; “not observed” does not mask a completed failing observation.

### US-qa-lane-leftovers-6: Preserve an alert until delivery

As the owner, I want a failed alert retained even if the condition recovers before the next run, so that no real QA failure disappears during a webhook outage.

Backlog: **CB-128**.

- **AC1 — fail then recover.** Given a red observation cannot be posted and the next run is green with a working webhook, when the next run delivers messages, then the original failure is delivered first with its original timestamp and `delivered late`, followed by the recovery.
- **AC2 — repeated post failure.** Given two consecutive delivery attempts fail, when state is read after the second run, then it still holds the first undelivered snapshot unchanged.
- **AC3 — malformed pending data.** Given the pending entry cannot be decoded, when the next run loads state, then it logs one warning without echoing raw content, drops only the malformed entry, and can still post its current result.
- **AC4 — normal path.** Given every post succeeds, when state does not change, then no message is sent; when state changes, exactly the existing change message is sent.

### US-qa-lane-leftovers-7: Every mutating command proves lock ownership

As a QA operator sharing one desktop, I want every mutating lane command bound to the current pass's unreported token, so that an expired pass cannot alter another pass's fixtures, cleanup flag, or SSH forward.

Backlog: **CB-129**.

- **AC1 — stale token denied.** Given pass B owns the lock and pass A supplies its old token, when A calls `restore`, `gui-done`, `forward-start`, or `forward-stop`, then each command exits non-zero, prints no token, and changes no fixture, cleanup flag, socket, PID file, or process.
- **AC2 — token required.** Given any of those commands is called without `--token`, when argument parsing runs, then it exits 2 before any state read or mutation.
- **AC3 — owner succeeds.** Given the current owner's token, when each command runs, then its existing behavior is preserved.
- **AC4 — hourly backstop.** Given the hourly backstop sees a stale marker, when it restores, then it first acquires the shared lock under its own unique token, holds it through restore, and releases it afterward. If acquisition fails, it logs `backstop skipped: lock held` and performs no restore.
- **AC5 — token privacy.** Given a complete pass, when its report, hourly log, assets, and Discord messages are searched, then no lock token appears.

## UX review

No story adds or changes a user-facing ContainerBar screen. Existing system prompts and Settings > Connections are used only as setup/test surfaces. Required UX behavior is therefore limited to operator handling:

- Copy remains exact and actionable for `authority-mismatch`, `desktop-busy`, `scope-breach`, `not observed (out of time)`, `keychain-authorization-required`, and late delivery.
- Agents never interact with Keychain or Local Network prompts; the one authorized person performs the documented one-time action.
- A blocked setup state names the missing prerequisite without exposing an authority string, identity hash, path, address, or password.

No UI-designer review is required unless implementation proposes a new app screen or changes customer-visible copy.

## Constraints

- **Priority/build order.** First finish CB-124's one-time signed-build and grant activation because it directly unblocks SSH cases. Next CB-131 makes operations reproducible, then CB-130 enforces the runtime boundary, then CB-129 closes the cross-pass mutation race. CB-126, CB-127, and CB-128 follow as one hourly-reliability wave. The project manager may interleave independent branches but must preserve those safety dependencies.
- **Platform.** QA execution is on the designated QA Mac or CI, never on Michael's MacBook. The lane remains macOS/Apple Silicon specific.
- **Locking.** A manual preflight that acquired the shared lock is an active pass until release or deadline. Operators never delete or bypass its lock.
- **Signing.** Apple Development is for QA builds only. Developer ID release signing and its key remain outside the QA Mac.
- **Scope.** Only `cbqa-` fixtures on the isolated rootless runtime. A non-fixture name is a refusal condition, not a filter rule.
- **Time.** Checks/backstop share 40 seconds; webhook gets at most 8 seconds; wrapper completes inside 55 seconds. Hard bounds must include DNS, connect, reads, retries, and cleanup.
- **Offline/network errors.** A network call not completed before the deadline is not observed. A completed negative response remains a real observation under its existing classification.
- **No process signals by name.** Existing PID-only forward handling and the global signal ban remain unchanged.

## Data and privacy notes

- Release checks send ordinary HTTPS requests to the existing GitHub release API, public appcast, public cask source, and the private Discord webhook. This work adds no destination.
- Hourly state stores check results, timestamps, and at most one pending red snapshot in the QA workspace. It must not store webhook URLs, lock tokens, certificate hashes, host addresses, or raw malformed pending content.
- The grant log stores only its existing non-secret fields: date, identity class, build, and actor. It does not store the authority string, identity hash, certificate serial, or password.
- The imported private key remains in Keychain. No key, certificate body, `.p12`, CSR, password, API token, or secret path enters source control, reports, screenshots, or Discord.
- No customer or end-user data is processed. No consent copy or billing behavior changes.

## Open questions and assumptions

1. **Should the lane ignore a non-fixture container?** Decision taken: **no**. It refuses before launch because the dedicated runtime's “only `cbqa-` fixtures” invariant is a safety boundary. No owner decision is needed unless product direction changes that isolation model.
2. **Which authority should the installed lane expect after setup?** Assumption: Apple Development while exercising the QA-signed normal build; Developer ID only when testing the released cask. The setting is renamed/documented by meaning, while its existing environment-variable name may remain for compatibility unless the architect approves a migration.
3. **Who answers the one-time prompts?** Existing decision retained: Michael answers Keychain **Always Allow** and grants Local Network once; Lucius and agents never enter a password or grant permissions.

No unresolved money, legal, billing, customer promise, or product-direction question remains.

## Out of scope

- Remediating or deleting the observed non-fixture container.
- Implementing CB-126 to CB-131 in this requirements branch.
- Creating or exporting certificates, rotating the Apple API key, or moving release credentials.
- Changing the app's connection UI, Local Network error UI, or container behavior.
- Adding daily test cases beyond the planner updates named below.

## Traceability

| Story | Backlog item | Test case / planner action |
|---|---|---|
| US-qa-lane-leftovers-1 | CB-131 | Proposed TC-CB-25, `QA lane SSH/operator preflight` |
| US-qa-lane-leftovers-2 | CB-124 | Existing TC-CB-22, TC-CB-23, TC-CB-05 |
| US-qa-lane-leftovers-3 | CB-130 | Proposed TC-CB-26, `QA runtime scope breach refuses launch` |
| US-qa-lane-leftovers-4 | CB-126 | Proposed TC-CB-27, `Hourly network calls obey wall-clock budget` |
| US-qa-lane-leftovers-5 | CB-127 | Proposed TC-CB-28, `Hourly budget exhaustion is not observed` |
| US-qa-lane-leftovers-6 | CB-128 | Proposed TC-CB-29, `Undelivered failure survives recovery` |
| US-qa-lane-leftovers-7 | CB-129 | Proposed TC-CB-30, `Mutating lane commands require current lock token` |
