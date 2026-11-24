# Requirements: ContainerBar daily QA passes 2026-11-19 to 2026-11-22

| | |
|---|---|
| Slug | `2026-11-23-daily-pass-batch` |
| Status | Ticketed (business analyst, 2026-11-23); ranking for project-manager review |
| Backlog | CB-142, CB-143, CB-144, CB-145, CB-146 (new); CB-140 and CB-124 (f) amended |
| Source | Daily 07:05 CT pass reports on the QA Mac, `<ws>/artifacts/containerbar-qa/runs/2026-11-{19,20,21,22}-daily-0705/report.md` and their `ax-dump.txt` / `status-item.json`, read read-only on 2026-11-23 |

This public document uses placeholders for private paths and hosts. No credential, identity hash or host address appears here.

## Problem

The daily pass has been BLOCKED four days running. Since the CB-138 and CB-141 tooling was installed (2026-11-20 06:29 CT, main `51f60f4`) each pass has ended with one PASS (TC-CB-01, a static check) and every UI case blocked. The QA Mac lost power and rebooted on 2026-11-19 08:59 CT and 2026-11-21 08:20 CT (`last reboot` on the QA Mac shows both). The installed app is ContainerBar 2.0.4-7 (Apple Development re-sign, commit `44a9303`), and the recipe on the QA Mac is byte-identical to `scripts/qa-lane/CONTAINERBAR_QA.md` on main.

## Reboot pattern: supported

The two `status-item-not-found` passes are the first passes after each reboot, and both `ax-dump.txt` files start with an empty released-PID line:

- 2026-11-20 `ax-dump.txt`: `released pids: ` / `menubar list: 9 entries, 0 match ContainerBar`. Report: "Execution gap: released-process launch prerequisite was not checked before discovery. During restore, Peekaboo reported APP_NOT_FOUND. The prescribed fallback relaunched the released app successfully. Therefore the discovery block does not establish a ContainerBar status-item defect."
- 2026-11-22 `ax-dump.txt`: `released pids: ` / `menubar list: 9 entries, 0 match ContainerBar`. The report does not name the cause; the empty PID line does.
- 2026-11-21 (not after a reboot; the app had been relaunched by the 11-20 restore): `released pids: 71640`, and AX found the status item (`2|1|1416|3|54|24|5|ContainerBar|5 of 6 containers running`).

homelab-it's read-only check on the QA Mac on 2026-11-23 confirms the mechanism: ContainerBar has no login item there (the only login item is a keep-awake utility), the hourly LaunchAgent is calendar-only, and the instance running this morning was started on 2026-11-22 at 07:06 by the daily pass's own restore. This is relayed by the orchestrator and was not read by the BA.

So ContainerBar is not running after a reboot (the lane may not toggle Launch at Login, and nothing else starts it), and the lane runs discovery anyway. The recipe already says it in prose (TC-CB-02: "If `pgrep -x ContainerBar` has no released PID: `open /Applications/ContainerBar.app`; within 10 s the status item shows"), but `capture-status-item` / `find-status-item` (`lane_discovery.find_status_item`) neither check nor launch, preflight relaunches only on marker or `gui-cleanup-pending` recovery (`lane_preflight.normalise_app`), and the agent skipped the prose step twice. A missing process is reported as `status-item-not-found`, which reads like an app defect. Lane defect, CB-142.

**Why one PASS since the install.** Nothing in the reports ties the 11-20 and 11-22 drops to the new tooling: they are the app not running after the reboots. The 11-21 drop is in the CB-138 `open_panel` path (found by AX, then `BLOCKED panel-not-capturable menubar=10 ax=1`), but the block line and `ax-dump.txt` record nothing about what the helper tried (click, AXPress, AX menu frame, region change, elapsed), so the cause cannot be attributed from the evidence. The 11-19 pass (CB-137 tooling) got five PASS with the agent improvising around panel targeting; since CB-137/138 a single discovery block blocks every UI case by design, which is why a block now costs the whole pass.

## Findings

| Date | Case | Report says (quoted) | Classification | Item |
|---|---|---|---|---|
| 11-20, 11-22 | TC-CB-02 then all UI | "BLOCKED status-item-not-found menubar=9 ax=0"; ax-dump "released pids: " (empty) | Lane: no launch-and-ready step before discovery after a reboot | **CB-142** (new) |
| 11-21 | TC-CB-02 then all UI | "open-panel returned exit 2: BLOCKED panel-not-capturable menubar=10 ax=1" | Lane: `open_panel` blocks with no diagnostics and no second attempt | **CB-143** (new) |
| 11-19 | open-panel | "One open-panel call reported ax-menu success but captured unrelated desktop content after failed menu observation" | Lane: the `ax-menu` capture path is still not pixel-verified on main (only the region fallback compares against the pre-click capture) | **CB-143** (new) |
| 11-19, 11-21 | restore | "One immediate relaunch returned error -600; a later launch succeeded"; "First relaunch returned error -600 while quit completed; one relaunch retry succeeded" | Lane: relaunch races the quit | **CB-142** (new) |
| 11-20 to 11-22 | restore | "UI restore unavailable: prescribed quit/import/relaunch fallback used"; 11-22: "absence of Settings/Sparkle and selected host cannot be verified ... gui-done deliberately not run" | Consequence of the discovery block, not a separate defect; the post-relaunch check is folded into CB-142 | **CB-142** |
| 11-19 | TC-CB-04/06/07/09/10/15/16/17 | "Direct window capture rejected layer != 0; tree-only could not resolve an accessible window; menu-bar bundle-id lookup failed"; "No reliable dashboard observation path" | Lane capability gap: no helper to read or press controls inside the open panel | **CB-144** (new) |
| 11-19 | TC-CB-14 | "Cancel attempted on its fresh exact-window coordinate receipt; error: 'No pressable accessibility element was found'"; "escalated to update-window-stuck" | Lane: the CB-139 Cancel path needs an AX element the pixel-only Sparkle window does not have | **CB-145** (new) |
| 11-19 | TC-CB-14 | "Checking at 90 seconds"; "appcast HEAD HTTP/2 200" | CB-140 evidence: second observation on the re-signed build | **CB-140** (run note) |
| 11-19 | TC-CB-08 | "Video missing (background-not-clear): safe background across app quit was not established; no recording attempted" | Lane: the recipe's clear-background precondition is never met; the video gap repeats | **CB-146** (new) |

Verification note: every quote above was read in the report or dump on the QA Mac on 2026-11-23. The reboot times were read from `last reboot`. The login-item and LaunchAgent facts come from homelab-it, relayed by the orchestrator. The 2026-11-20 06:29 CT install time and the installed build come from the work order.

## Lane build order (ranked)

1. **CB-142** launch and ready before discovery: two of the three post-install passes were lost to it, and every pass after a power cut will be.
2. **CB-143** `open_panel` second attempt, diagnostics and pixel check: the one non-reboot pass lost to it, and it guards against a false PASS.
3. **CB-144** panel control targeting: with 142 and 143 in, the pass reaches the panel; eight cases still need controls inside it.
4. **CB-140** lane run (not builder work): runs once 142 and 143 are installed, in parallel with 144.
5. **CB-145** positional Cancel for TC-CB-14.
6. **CB-131** operator docs (unchanged).
7. **CB-146** TC-CB-08 clear background.
8. Then CB-130 → CB-129 → CB-126/127/128 as before.

## CB-124 (f) housekeeping: keep waiting

Its condition, "the first daily pass with no BLOCKED case caused by the lane", has not been met: 11-19 to 11-22 all had lane-caused BLOCKED cases (11-20 and 11-22 included: the lane, not the app, failed to start the app). The backups hold pre-CB-137 tooling, so their rollback value is small, but removing them earlier gains nothing either. The expected trigger is now the first pass after CB-142 and CB-143 are installed.

## Open questions

None that need Michael. Assumption: the lane starts the app. A login item on the QA Mac is at most an optional homelab-it step and not the fix. A login item would change the state the app's own Launch at Login setting reports, and the lane is forbidden to touch that toggle.

## Out of scope

App code (no app defect is established by these passes); CB-140's diagnosis itself; the hourly check (whether it posted `app-not-running` after each reboot was not checked).

## Traceability

| Item | Lane / app | Test case |
|---|---|---|
| CB-142 | lane | TC-CB-02, TC-CB-33; proposed TC-CB-34 (cold start after reboot) |
| CB-143 | lane | TC-CB-02, TC-CB-33; proposed TC-CB-35 (panel block diagnostics) |
| CB-144 | lane | TC-CB-04, 06, 07, 09, 10, 15, 16, 17 |
| CB-145 | lane | TC-CB-14 |
| CB-146 | lane | TC-CB-08 |
| CB-140 | undecided (lane run) | TC-CB-14 |
