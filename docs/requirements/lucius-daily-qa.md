# Requirements: Lucius daily QA pass for ContainerBar

| | |
|---|---|
| Slug | `lucius-daily-qa` |
| Status | Draft (business analyst, 2026-10-14); design pending in `docs/architecture/lucius-daily-qa.md` (solution architect, branch `req/containerbar-factory-intake-arch`) |
| Backlog | CB-100 to CB-106 (High) |
| Owner of the run | Lucius (OpenClaw agent on the Agent Mac mini) |
| Reviewer of the run | The orchestrator relays results; the owner approves defects into the backlog |

This file is public (the repository is public). It names no host addresses, user names, channel ids, key material, or private endpoints. Where the run needs one, it says `<placeholder>` and the value lives in the agent workspace on the Mini.

## 1. Problem

ContainerBar's only automated checks today are CI (`swift-ci.yml` on GitHub-hosted runners) and four Prowl hunts (`prowl-qa.yml` on the Mini's self-hosted runner) that run a **Debug hunt-mode build** against `FixtureDockerAPIClient`: six fixed in-memory containers, a throwaway defaults suite, no real daemon, no SSH, no Sparkle. Nothing exercises the build users actually install (the notarized zip or the Homebrew cask) against a real container runtime, so a whole class of defect is invisible until a user hits it:

- Defects that only exist on the real transport: multiplexed log frames leaking into log text (CB-070), a peer-closed connection reported as "daemon may be incompatible" (CB-071), the aggregate memory denominator inflated by unlimited containers (CB-069), dual-stack port duplication (CB-079). Each was found by a code audit, not by a run.
- Defects that only exist in the distributed artifact: CB-041 (a resource-bundle path that worked from the build tree and crashed off it) is the precedent; the clean-machine smoke launch in `docs/RELEASING.md` is still a manual console step (CB-058).
- Settings that survive (or do not survive) a relaunch or an upgrade (CB-075).

How we know: the 2026-09-18 audit filed CB-069 to CB-098 from code reading alone; `docs/RELEASING.md` and CB-058 record that the launch half of the smoke test is manual; the owner asked on 2026-10-14 for Lucius to run automated QA on ContainerBar "throughout the day, similar to Sentwise". Sentwise already has this lane: a standing QA recipe file and briefs in Lucius' workspace, evidence under `artifacts/sentwise-qa/runs/`, a report per run, results posted to the product's Discord channel, a zero-token hourly check that posts failures only, and one summary a day.

## 2. Goal and non-goals

**Goal.** Every weekday, without the owner doing anything, Lucius proves on the Agent Mini that the **currently released** ContainerBar installs, launches, connects to a real container runtime, lists and acts on disposable QA containers, keeps its settings across a relaunch, and can check for updates; and the owner learns about a regression from one Discord message with evidence, the same day it appears.

**How we know it worked.** Measured weekly in the company metrics: a daily-pass clean rate (scheduled runs that ran and passed, out of scheduled runs), zero runs that touched anything outside the QA fixture, and the number of defects the pass found before a user did.

**Non-goals.**
- Not a replacement for CI or the Prowl hunts; those keep gating PRs on fixture data.
- Not branch or PR QA. Verifying a builder's branch is a separate, orchestrator-fired brief (factory Stage 3); the daily pass tests the released build only, plus the release-day upgrade case.
- No accessibility audit (CB-081 keeps the owner's manual VoiceOver pass as its check), no screenshots for marketing (CB-099), no performance benchmarking beyond the one idle-wakeup probe used by CB-073.
- No code or script changes in this repository as part of this brief. Any repo change the design needs (for example CB-058's automated console launch, or hiding hunt mode from release builds per CB-090) is its own backlog item and branch.
- No Docker Desktop on any Mac, ever (company rule).

## 3. Users and roles

| Who | What they do in this lane |
|---|---|
| Lucius (OpenClaw, Agent Mini) | Runs the scheduled passes from a standing recipe file and a daily brief, drives the UI with Peekaboo, writes evidence and the report, posts the result. Has no write access to this repository or the ops repo. |
| Orchestrator (Claude Code) | Writes and maintains the brief and the recipe file, fires release-day runs, checks the CI-idle precondition for fired runs, relays each result into the ops inbox, turns proposed defects into backlog items via the business analyst. |
| Homelab IT specialist | Provisions and maintains the QA container runtime and the QA fixture containers on the chosen host (CB-100). |
| Solution architect | Chooses the runtime topology and writes the design (`docs/architecture/lucius-daily-qa.md`). |
| Owner (Michael) | Reads the Discord message, approves defects, answers the open questions below. Never needs to touch the Mini for a normal run. |

## 4. Definitions used in the acceptance criteria

- **QA runtime**: the container runtime the Mini's ContainerBar connects to during a pass (see Open question 1). Whatever is chosen, it runs **only** QA fixture containers.
- **QA fixture set**: containers created by the setup in CB-100, every one named with the prefix `cbqa-` and carrying the label `com.tookes.containerbar.qa=1`. Minimum set, from small public images already pulled (no pull during a pass):
  - `cbqa-web`: running, no memory limit, published `18080:80/tcp` and `18080:80/udp`.
  - `cbqa-logs`: running, no TTY, no memory limit, prints the exact lines `cbqa-line-1`, `cbqa-line-2`, `cbqa-line-3` to stdout and `cbqa-err-1` to stderr at start, then sleeps.
  - `cbqa-limited`: running, memory limit 256 MiB.
  - `cbqa-stopped`: created and exited (status Exited).
  - `cbqa-target`: running; the only container the pass may stop, start, or restart.
- **QA host entry**: the one host configured in the Mini's ContainerBar settings that points at the QA runtime, named `QA Runtime`. It is the selected host during every pass.
- **Released build**: the version in the latest non-draft GitHub release of `michaeltookes/ContainerBar` (today 2.0.4, build 7), signed by the owner's Developer ID, notarized and stapled.
- **Pass window**: the time box of one run (assumption: 20 minutes for the full pass, 1 minute for the hourly check).
- **Evidence root**: `~/.openclaw/workspace/artifacts/containerbar-qa/runs/<YYYY-MM-DD>-<kind>-<HHMM>/` on the Mini, where `<kind>` is `daily`, `hourly`, or `release`.

## 5. User stories and acceptance criteria

### US-lucius-daily-qa-1: A QA container runtime the Mini can reach that cannot reach production

As the owner, I want ContainerBar on the Mini to monitor a container runtime that holds only disposable QA containers, so that a daily pass can start, stop, and read logs from real containers without any path to a production service.

Backlog: **CB-100**. Design: solution architect (runtime topology). Execution: homelab IT specialist.

- **AC1 (runtime reachable).** Given the QA runtime is provisioned, when Lucius runs the runtime's own list command against it from the Mini (for example `podman ps -a --filter label=com.tookes.containerbar.qa=1 --format '{{.Names}} {{.Status}}'`), then exactly the five fixture containers in section 4 are listed with the stated states, and nothing else.
- **AC2 (fixture only).** Given the QA runtime, when Lucius lists **all** containers on it (no filter), then every container name starts with `cbqa-`. Any other name is a FAIL of the precondition and the pass stops before launching ContainerBar.
- **AC3 (no production path).** Given the credentials and sockets present on the Mini for this lane, when an operator tries to list containers on the production daemon of the homelab Docker host using only those credentials, then the attempt is refused (permission denied, no such socket, or no key accepted). The design records which mechanism enforces this.
- **AC4 (reset).** Given any fixture container is missing or in the wrong state (for example `cbqa-target` left stopped by an aborted run), when the documented reset command runs, then AC1 holds again within 2 minutes, and the reset touches only `cbqa-` containers.
- **AC5 (runtime down, unhappy path).** Given the QA runtime is stopped (the Podman machine is stopped, or the remote QA daemon is unreachable), when the pass precondition check runs, then the pass is marked BLOCKED with reason `qa-runtime-down`, the Discord message says so in one line, and no ContainerBar case is attempted.
- **AC6 (no Docker Desktop).** Given the Mini, when `ls /Applications | grep -i docker` runs, then it prints nothing; the design never installs Docker Desktop.

### US-lucius-daily-qa-2: A standing recipe file and evidence layout in Lucius' workspace

As Lucius, I want one recipe file that tells me how to find and drive ContainerBar's status item, dashboard, Settings panes, and dialogs on the Mini, so that each pass follows known steps instead of rediscovering the UI and two runs of the same case produce comparable evidence.

Backlog: **CB-101**. Mirrors `SENTWISE_QA.md`.

- **AC1 (file exists).** Given the workspace, when the orchestrator opens `~/.openclaw/workspace/CONTAINERBAR_QA.md`, then it contains: the released-build verification commands; the status-item click recipe; how to tell the released app's status item from the Prowl hunt build's (bundle id `com.tookes.ContainerBar.hunt`) if both are present; the Settings pane names (General, Connections, Sections, About) and the accessibility identifiers the pass may use (`refreshIntervalPicker`, `testConnection`, `refreshLogs`, `logs-panel-close`, `aboutVersion`, `dismissActionError`); the forbidden controls list (AC4); the fixture set; the evidence root; and the restore steps.
- **AC2 (layout).** Given a finished run, when the orchestrator lists its evidence root, then it contains `report.md`, `assets/<TC-id>/NN-<slug>.png` for every executed step, and one `assets/<TC-id>.mov` per case, using the report shape of the existing Lucius brief template.
- **AC3 (no secrets in assets).** Given any asset in the evidence root, when it is reviewed, then it shows no SSH private key, password, token, real host address, or non-fixture container name. A screen capture that would show one is cropped (`screencapture -R`) or not taken, and the step is marked `blocked` instead.
- **AC4 (forbidden controls).** Given the recipe, when it lists forbidden actions, then it includes: Remove container on any container; any action on a container whose name does not start with `cbqa-`; Remove Host or Delete Section on any entry other than one the run itself created; "Install Update" in a Sparkle dialog during a daily pass; the Launch at Login toggle; the global keyboard shortcut recorder.
- **AC5 (stale recipe, unhappy path).** Given a recipe step whose element is not found (the UI changed in a release), when Lucius follows it, then the step is marked `blocked` with the actual `peekaboo see` element list attached as text in the report, the case does not improvise a different click path, and the report's "Defects and proposed backlog items" names the recipe as stale.

### US-lucius-daily-qa-3: Install path and released-build integrity

As the owner, I want each daily pass to confirm the Mini runs exactly the released build, and on release day to install the new build from both the cask and the notarized zip, so that a broken artifact, a wrong signature, or a stale cask is caught before users install it.

Backlog: **CB-102**. Related: CB-058 (automating the console launch of the zip), CB-086 (validator from a clean checkout).

- **AC1 (daily, version matches).** Given the latest GitHub release is version V, when the pass reads `defaults read /Applications/ContainerBar.app/Contents/Info.plist CFBundleShortVersionString`, then it prints V. If it prints anything else, the pass is marked FAIL with reason `stale-install` and continues the remaining cases against the installed build, saying so in the report.
- **AC2 (daily, signature).** Given the installed app, when the pass runs `codesign --verify --deep --strict /Applications/ContainerBar.app`, `spctl --assess --type execute /Applications/ContainerBar.app`, and `xcrun stapler validate /Applications/ContainerBar.app`, then all three exit 0, and `codesign -dv` names the owner's Developer ID authority (the expected authority string lives in the recipe file, not here).
- **AC3 (daily, launch).** Given ContainerBar is not running, when Lucius launches it from the console session with `open /Applications/ContainerBar.app`, then within 10 seconds a ContainerBar status item is visible in the menu bar (screenshot `01-status-item.png`) and `pgrep -x ContainerBar` prints one PID. If no status item appears within 10 seconds, the case is FAIL with the last 50 lines of `log show --last 2m --predicate 'process == "ContainerBar"'` attached as text.
- **AC4 (release day, cask).** Given a new release V+1 has been published and the tap updated, when the orchestrator fires the release brief and Lucius runs `brew upgrade --cask containerbar`, then the installed version reads V+1, AC2 and AC3 pass, and the saved QA host entry and refresh interval from before the upgrade are unchanged (see story 5).
- **AC5 (release day, zip).** Given the same release, when Lucius downloads `ContainerBar.zip` from the release into a new temporary directory, extracts it, and runs the same three checks as AC2 against the extracted app, then all pass, the extracted app launches from the console session (status item visible), is quit, and the temporary directory is deleted. This closes the manual step recorded in `docs/RELEASING.md` for that release.
- **AC6 (release day, Sparkle upgrade path).** Given a second copy of the previous release V is installed from its zip into a temporary location, when Lucius launches it and chooses "Check for Updates..." in Settings > About, then Sparkle offers V+1 with the release notes from the appcast. Lucius stops at the offer (no install) and quits that copy.
- **AC7 (unhappy path, Gatekeeper).** Given an artifact fails any of `codesign`, `spctl`, or `stapler`, when the check runs, then the run is FAIL with the exact tool output quoted in the report, the Discord message starts with `QA FAIL` and names the failing check, and Lucius does not launch that artifact.

### US-lucius-daily-qa-4: Dashboard, container list, actions, and logs against the QA runtime

As the owner, I want the daily pass to open the dashboard, see the fixture containers with correct state and metrics, stop and start one container, and read its logs, so that the core of the product is verified on a real runtime every day.

Backlog: **CB-103**.

- **AC1 (connected list).** Given the QA host entry is selected and the fixture set is in its reset state, when Lucius clicks the status item, then the dashboard opens and shows all five `cbqa-` containers within one refresh interval; `cbqa-web`, `cbqa-logs`, `cbqa-limited`, and `cbqa-target` are shown as running and `cbqa-stopped` as stopped (or hidden, if "Show stopped containers" is off, which the recipe states).
- **AC2 (counts and metrics).** Given the dashboard is open, when Lucius reads the Running pill and the General Stats grid, then the Running count equals 4, the CPU and RAM tiles show numbers with units, and the RAM tile's denominator is not larger than the QA runtime's total memory (as printed by the runtime's `info` command). The last check fails on today's build because of CB-069; the pass records it as a known failure linked to CB-069 rather than a new defect.
- **AC3 (stop and start).** Given `cbqa-target` is running, when Lucius uses the card's quick action to stop it, then within 2 refresh intervals the card shows the stopped state and the runtime's list command shows `cbqa-target` as Exited; when Lucius then starts it, the card shows running again and the runtime agrees. Screenshots before, after stop, after start.
- **AC4 (restart).** Given `cbqa-target` is running with start time T (from the runtime's inspect), when Lucius chooses Restart from the Container Actions menu, then the runtime reports a start time later than T within 30 seconds and the card is running.
- **AC5 (logs).** Given `cbqa-logs` is running, when Lucius opens its logs (logs panel and the log viewer window), then the text contains the lines `cbqa-line-1`, `cbqa-line-2`, `cbqa-line-3`, and `cbqa-err-1` in order, and no line starts with a control character or a replacement character before `cbqa-`. The second clause is the CB-070 check; until CB-070 ships it is recorded as a known failure if it fails.
- **AC6 (detail popover).** Given the dashboard, when Lucius opens `cbqa-web`'s card details, then the popover shows the image, the published port 18080, and no duplicated port rows (CB-079 check, known failure until it ships).
- **AC7 (runtime goes away, unhappy path).** Given the dashboard is connected, when Lucius stops the QA runtime (Podman machine stop, or the design's equivalent) and waits two refresh intervals, then ContainerBar shows a disconnected or not-running message and no stale container is presented as running; the message text is captured verbatim. When the runtime is started again, then ContainerBar shows the five containers again within two refresh intervals without being relaunched. If the message reads "Invalid response from Docker daemon" or "Docker connection not configured", the report links CB-071 or CB-077.
- **AC8 (stale state, unhappy path).** Given `cbqa-target` was just stopped outside the app with the runtime's own stop command and ContainerBar has not refreshed yet, when Lucius clicks Stop on its card, then the app either shows an action error banner or treats it as a no-op, and in both cases the card shows stopped after the next refresh; the app does not crash or hang. Any banner text is captured verbatim and dismissed with `dismissActionError`, and `cbqa-target` is started again before the next case.
- **AC9 (scope guard).** Given any step of this story, when an action control is about to be clicked, then the container name on that card starts with `cbqa-target` (for stop/start/restart) or `cbqa-` (for logs and details). Otherwise the step is not taken and the run is marked BLOCKED with reason `scope-guard`.

### US-lucius-daily-qa-5: Settings persistence and the update check

As the owner, I want the pass to change a few settings, quit and relaunch, and see them kept, and to check for updates without installing anything, so that a persistence regression (CB-075 class) or a broken appcast is caught the day it appears.

Backlog: **CB-104**.

- **AC1 (persist across relaunch).** Given the refresh interval is the recipe's baseline (assumption: 10 seconds) and "Show stopped containers" is on, when Lucius sets the interval to 30 seconds with `refreshIntervalPicker`, turns "Show stopped containers" off, quits ContainerBar from its menu, and relaunches it, then the General pane shows 30 seconds and the toggle off, and the dashboard hides `cbqa-stopped`.
- **AC2 (restore).** Given AC1 passed, when Lucius restores the baseline values and relaunches once more, then the baseline values are shown. The report's run notes state the restored values.
- **AC3 (hosts survive).** Given the QA host entry exists before the relaunch, when the app relaunches, then Settings > Connections still lists `QA Runtime` with the same connection type and runtime, and it is still the selected host. A missing host entry is FAIL with severity P1 and links CB-075.
- **AC4 (connection test).** Given Settings > Connections with `QA Runtime` selected, when Lucius clicks `testConnection`, then the pane shows a success result within 10 seconds. With the runtime stopped (only during AC7 of story 4, never as an extra step), the same click shows a failure result naming the reason.
- **AC5 (update check, up to date).** Given the installed version equals the latest release, when Lucius clicks "Check for Updates..." in Settings > About, then Sparkle reports that ContainerBar is up to date, and `aboutVersion` shows the installed version and build.
- **AC6 (update check, newer exists, unhappy path).** Given the appcast advertises a newer version than the installed one (a release happened and the release-day brief has not run yet), when the check runs, then the pass records `update-available <version>` in the report, presses "Remind Me Later" (never "Install Update"), and marks the case PASS with a note; the orchestrator fires the release brief.
- **AC7 (appcast unreachable, unhappy path).** Given the appcast URL cannot be fetched (`curl -sSfI https://michaeltookes.github.io/ContainerBar/appcast.xml` exits non-zero), when the update check runs, then the case is BLOCKED with reason `appcast-unreachable` and the Sparkle error dialog text is captured verbatim.

### US-lucius-daily-qa-6: Schedule, safety preconditions, and restoring the Mini

As the owner, I want the passes to run on a schedule, refuse to run while CI is using the Mini's desktop, and always leave the Mini as they found it, so that QA never fights CI, never leaves a container stopped, and never needs me to clean up.

Backlog: **CB-105**.

- **AC1 (schedule).** Given a weekday, when the schedule fires, then one full pass runs at each scheduled time (assumption: 10:00 and 15:00 Central) and a zero-token hourly check runs from 08:00 to 20:00 Central. The hourly check only verifies that `pgrep -x ContainerBar` finds the process, that the installed version equals the latest release (cached once a day), and that the QA runtime lists the five fixtures; it uses no model tokens and posts only on failure.
- **AC2 (CI idle).** Given any `actions-runner` job is running on the Mini (`pgrep -f actions-runner/_work` prints a PID), when a full pass is about to start or about to start a case, then it waits up to 10 minutes for the runner to go idle, rechecking each minute; if it is still busy, the run is BLOCKED with reason `ci-busy` and no ContainerBar case runs. (Precedent: the Sentwise v0.2.1 live checks were BLOCKED 7/7 when a CI test host replaced the app mid-run.)
- **AC3 (QA lock).** Given another Lucius desktop brief holds the QA lock (Sentwise QA, a device task), when a ContainerBar pass is due, then it waits up to 10 minutes and then reports BLOCKED with reason `desktop-busy`; it never runs concurrently with another desktop brief.
- **AC4 (restore).** Given a run ends for any reason (pass, fail, blocked, time box exceeded), when the restore step runs, then: `cbqa-target` is running, every fixture is in its reset state (story 1 AC4 run if needed), ContainerBar is running with the baseline settings, no extra host entry created by the run remains, no Sparkle dialog or Settings window is open, and the run notes list each restore action. A restore that fails posts to `#lucius-updates` as a request for help.
- **AC5 (keychain or TCC prompt, unhappy path).** Given a system dialog the recipe does not cover appears (Keychain password prompt, a TCC permission prompt, a Gatekeeper dialog), when Lucius sees it, then he does not type a password or grant a permission, captures a cropped screenshot, marks the run BLOCKED, and posts one line to `#lucius-updates` asking the owner to act.
- **AC6 (no production, no secrets).** Given any run, when its commands are reviewed from the run log, then none targets a host other than the QA runtime, none uses `kill`, `pkill`, or `killall` (quitting ContainerBar is done through its own Quit menu item or `osascript -e 'quit app "ContainerBar"'`), and none prints a secret into the report.

### US-lucius-daily-qa-7: Report, Discord message, and defect intake

As the owner, I want one Discord message per full pass with the verdict and the failing evidence first, and failures turned into backlog items without me copying anything, so that I can read QA results in a minute and act on them.

Backlog: **CB-106**.

- **AC1 (report).** Given a finished full pass, when the orchestrator opens `report.md` in its evidence root, then it has the brief template's shape: a header table (date, build, runner, verdict with counts), a summary table with one row per case, per-case steps with asset paths, a "Defects and proposed backlog items" section, and run notes including state restored.
- **AC2 (Discord, pass).** Given every case passed or was a known failure linked to an open CB item, when the run posts, then exactly one message goes to the ContainerBar channel (Open question 3) starting `QA PASS — ContainerBar <version> — <date> <HH:MM>` with counts and the report path; on a clean day only the first full pass posts a message (one summary per day, as Sentwise), later clean passes post nothing.
- **AC3 (Discord, fail).** Given at least one case failed that is not a known failure, when the run posts, then the message starts `QA FAIL`, names the failing case ids, and attaches the failing steps' screenshots first (videos only if each is under 25 MB).
- **AC4 (known failures stay quiet).** Given a case fails exactly as a linked open CB item predicts (for example CB-069's denominator), when the report is written, then it is listed under "Known failures" with the CB id and does not by itself turn the verdict to FAIL; when that CB item is resolved, the recipe drops it from the known list and the same failure becomes a FAIL.
- **AC5 (inbox relay).** Given a run finished, when the orchestrator processes it, then one line lands in the ops inbox in the form `ContainerBar#qa-daily | lucius | done|qa-found|blocked | artifacts/containerbar-qa/runs/<run> | <one sentence>`.
- **AC6 (defect intake).** Given a report proposes a defect, when the business analyst processes it, then it becomes a new `CB-` item in `docs/backlog.md` with the repro steps from the report, the evidence path, and an Acceptance block, or it is appended as evidence to the existing item it duplicates; it is never filed twice.
- **AC7 (Discord unavailable, unhappy path).** Given `openclaw message send` fails, when the run reports, then the report is still written, the failure to post is recorded in its run notes, and the orchestrator's inbox line says `post-failed`.

## 6. Constraints

- **Platform.** Apple Silicon only, macOS 14+ (`depends_on arch: :arm64`). The Mini runs the released build only; it keeps `~/qa/ContainerBar` for CI, which the pass never builds or launches.
- **Shared desktop.** The Mini's self-hosted runners run `prowl-qa` for this repo (hunt build, bundle id `com.tookes.ContainerBar.hunt`, its own status item) and for Sentwise. Story 6 AC2 applies to every full pass and every release brief. CB-090 item 1 (a concurrency group for `prowl-qa.yml`) and ops backlog 6l (separate runner user) reduce the collision rate but do not remove the precondition.
- **Hunt mode in release builds.** Release builds still contain the hunt-mode switch (CB-090 item 4). The pass must never set `CONTAINERBAR_HUNT_MODE`; the released app must show the QA runtime's containers, not the six fixtures. Seeing the fixture names (`FixtureDockerAPIClient`) in a daily pass is a FAIL.
- **Sparkle.** A daily pass checks for updates but never installs; installs happen only in the release brief. CB-074 (updater started in hunt mode) is a related defect on the CI side.
- **Container runtime.** No Docker Desktop. ContainerBar supports a local Unix socket (Docker or the Podman machine socket under the user's home) and a remote host over an SSH tunnel or TCP+TLS. Access to a Docker or Podman API socket is equivalent to full control of that daemon, so the QA runtime must be a daemon that runs nothing but QA fixtures (story 1 AC3).
- **Mini resources.** The Mini also hosts the CI runners, the OpenClaw gateway, and a local embedding server. A Podman machine adds a VM; the design states its CPU and memory allocation and whether it runs always or only during a pass.
- **Cost.** Lucius runs on the owner's ChatGPT subscription. The hourly check is zero-token; full passes are model-driven and time-boxed (20 minutes assumed).
- **Process control.** On the Mini an agent may stop only a process it started, by PID. ContainerBar is quit through its own menu or an `osascript quit`, never by signal. Nothing in this lane runs on the owner's MacBook or development Mini.
- **Public repository.** This file and the backlog are public mirrors. Host addresses, user names, channel ids, key paths, and the Developer ID authority string live in the workspace recipe file on the Mini.

## 7. Data and privacy notes

- **What leaves the Mini.** The report path and summary text, and selected screenshots and videos, go to a private Discord channel. Assets show only fixture containers and the QA runtime's name. No asset is committed to this public repository.
- **What is stored.** Evidence under `~/.openclaw/workspace/artifacts/containerbar-qa/runs/` on the Mini; retention follows the Sentwise runs (assumption: 30 days, then pruned by the workspace's existing housekeeping).
- **Credentials.** If the design uses a remote QA daemon over SSH, the key is dedicated to this lane, has no passphrase prompt that would block an unattended run (agent-loaded or Keychain-held), is authorized only for the QA user on the QA host, and is never printed, screenshotted, or posted. ContainerBar uses the SSH agent; it stores no key material itself.
- **ContainerBar's own data.** The app keeps hosts, sections, and settings in its user defaults on the Mini. The pass reads and changes them only through the UI (story 5), restores the baseline, and never edits the preferences file directly in a daily pass.
- **No consent copy changes.** The app sends nothing to Genkei services; this lane adds no telemetry.

## 8. Open questions (with the assumption taken)

1. **Which container runtime does the Mini monitor?** Options: (a) Podman on the Mini (rootless Podman machine, local socket); (b) a remote QA daemon on the homelab Docker host over ContainerBar's SSH tunnel, as a separate rootless daemon under a dedicated QA user, never the production daemon; (c) both, Podman daily and remote weekly. **Assumption: (a) Podman on the Mini is the daily target**, because it cannot reach production by construction, exercises the Podman runtime path, and needs no network dependency; a remote SSH case can be added later as its own story if the architect recommends (c). Solution architect decides; the owner confirms.
2. **How often is "throughout the day"?** **Assumption:** two full passes on weekdays (10:00 and 15:00 Central, inside the owner's day-job block when agents run unattended) plus a zero-token hourly liveness check 08:00 to 20:00 Central, failures only, one summary message a day. Weekends: one full pass at 10:00.
3. **Where do results post?** **Assumption:** a new private `#containerbar` channel in the same Discord server as `#sentwise`, created by the owner; until it exists, results post to `#lucius-updates`.
4. **May the pass ever use "Remove container"?** **Assumption: no** in the daily pass. A weekly case may remove a container the run itself created from a fixture image (`cbqa-ephemeral-<date>`) once the architect confirms the scope guard; until then Remove is covered only by unit tests and the Prowl fixture hunts.
5. **Does the Mini get its own ContainerBar install, separate from any copy the owner uses elsewhere?** **Assumption: yes**; the Mini's install exists only for QA, its settings hold only the `QA Runtime` host, and nothing the owner configures on the MacBook is synced to it.

## 9. Out of scope

- Building, signing, or notarizing anything on the Mini (release builds stay on the release path in `docs/RELEASING.md`).
- QA of branches and PRs (separate orchestrator-fired brief per story, Stage 3).
- TCP+TLS host coverage (no QA TLS daemon exists; add later if the design provisions one).
- Multi-display behaviour (CB-076 item 3), VoiceOver (CB-081), localisation.
- Changes to the Prowl hunts (CB-098) and CI (CB-090), which stay in their own items.

## 10. Traceability

| Story | Backlog item | Depends on | Test cases (planner adds) |
|---|---|---|---|
| US-lucius-daily-qa-1 | CB-100 | architect design | TC-qa-1-* |
| US-lucius-daily-qa-2 | CB-101 | CB-100 | TC-qa-2-* |
| US-lucius-daily-qa-3 | CB-102 | CB-101; release-day half benefits from CB-058 | TC-qa-3-* |
| US-lucius-daily-qa-4 | CB-103 | CB-100, CB-101; known failures CB-069, CB-070, CB-071, CB-077, CB-079 | TC-qa-4-* |
| US-lucius-daily-qa-5 | CB-104 | CB-101; related CB-074, CB-075 | TC-qa-5-* |
| US-lucius-daily-qa-6 | CB-105 | CB-100; related CB-090 item 1, ops 6l | TC-qa-6-* |
| US-lucius-daily-qa-7 | CB-106 | CB-105 | TC-qa-7-* |

Existing items enriched with Acceptance blocks in the same branch (`docs/backlog.md`): CB-069 to CB-080. Their QA checks reference the fixture set in section 4.
