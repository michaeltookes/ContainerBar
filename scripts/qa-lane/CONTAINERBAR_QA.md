# ContainerBar QA recipe (CB-101)

The standing recipe for the ContainerBar daily pass on the QA Mini. The daily brief (from
`brief-template.md`) sets the session id, evidence root and schedule; where the two differ, the
brief wins. Versioned as the repo's `scripts/qa-lane/CONTAINERBAR_QA.md` and copied by
`install.sh`; never edit the workspace copy.

## Rules for the whole pass

- **Run every command from the workspace root** the lane tools use: start each shell call with
  `cd "${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}"` (`cbqa_lane.py` is in `tools/containerbar-qa/`).
- **Lock token.** `preflight` prints `note: lock token <token>`. Copy that exact value into
  the run notes and pass it to every `normalise`, `case-gate` and `release` call as
  `--token "<token>"`. Never read a token from `session.json` or reuse an older run's token.
- **Never** `kill`, `pkill` or `killall`. Quit ContainerBar with its own Quit button or
  `osascript -e 'quit app "ContainerBar"'`. The only process the pass stops is its SSH forward,
  through `cbqa_lane.py forward-stop`.
- Preflight holds the desktop lock: never wrap Peekaboo calls in `device_lock.py`.
- Touch only the QA runtime (`ssh cbqa-ctl <verb>`, `cbqa-tunnel`, the `QA Runtime` hosts) and
  only `cbqa-` containers. No secret, key, address, token or real hostname in any asset,
  report or post; crop to the app window or take no screenshot and mark the step `blocked`.
- **Never improvise.** An element the recipe names that is not there makes the step `blocked`:
  attach the `peekaboo see --json` element list as text and name this recipe stale under
  "Defects and proposed backlog items".

## Private values (never in this file)

Read with `grep '^KEY=' qa/containerbar/lane.env | tail -n1 | cut -d= -f2-`, never `source`: `CBQA_DAILY_TARGET` (ContainerBar channel), `CBQA_ALERT_TARGET` (`#lucius-updates`),
`CBQA_DEVELOPER_ID_AUTHORITY` (the expected `Authority=Developer ID Application: ...` line),
`CBQA_RUNNER_NAMES`. The baseline is `qa/containerbar/baseline.plist`. Local Network grants
are recorded in `qa/containerbar/local-network-grants.log`, one line per grant:
`<YYYY-MM-DD> | <version or build> | <identity: developer-id or qa-apple-development> | <who>`.

## The app

- Released app: `/Applications/ContainerBar.app`, bundle id `com.tookes.ContainerBar`. Target it
  as `--app com.tookes.ContainerBar` (or `--app "PID:<pid>"` with the PID below).
- **Hunt build** (Prowl PR gate): bundle id `com.tookes.ContainerBar.hunt`, path containing
  `/.prowl/DerivedData/`, the same name and status-item title. Never click, quit or screenshot it.
  Tell them apart by command line: `pgrep -x ContainerBar | xargs -n1 ps -o pid=,command= -p`;
  the released PID's command starts with `/Applications/ContainerBar.app/`.
- **Status item.** `peekaboo menubar list --json`; pick the entry titled `ContainerBar` (from the
  release containing CB-107: identifier `containerBarStatusItem`). If two `ContainerBar` entries
  exist (hunt build left running) and the frames cannot be tied to the released PID, the step is
  `blocked` with the list. Open it with a positional click on the frame centre:
  `peekaboo click --at <x>,<y> --global --foreground --no-auto-focus` (y = 15), wait 0.8 s,
  screenshot. Re-read the frame each time, never assume an index.
- Settings panes: **General**, **Connections**, **Sections**, **About**. Open Settings from the
  panel's gear button. Close Settings with its window close button before the restore.
- **Selectors are release-aware.** Use identifiers only when the installed version is at or
  above the `fixed-in` of the item that added them (table at the end); otherwise use the label.

| Element | Identifier (when released) | Label fallback (installed 2.0.4) |
|---|---|---|
| Settings / Quit / Refresh buttons | `openSettings` / `quitApp` / `refreshContainers` | help text `Settings` / `Quit ContainerBar` / `Refresh` |
| Container card | `containerCard-<slug>` | card text `cbqa-...` |
| Stop / Start quick action | `containerStop-<slug>-<short-id>` / `containerStart-<slug>-<short-id>` | `Stop container cbqa-target` / `Start container cbqa-target`, after hovering the card |
| Logs button (action bar) | `actionBar-logs` | button `Logs` (the panel's `View Logs` is a heading, never click it) |
| Logs row for a fixture | `logs-panel-container-<slug>-` prefix | the row button labelled with the container name, e.g. `cbqa-logs` (2.0.4 id `logs-panel-container-<full id>`) |
| Log text / refresh / close | `logsPanelText` / `refreshLogs` / `logs-panel-close` | the log text area / `Refresh` / `logs-panel-close` (in 2.0.4) |
| Connection state / error dismiss | `connectionStatus` / `dismissActionError` | header text / `Close` |
| Refresh interval / show stopped | `refreshIntervalPicker` / `showStoppedToggle` | `Refresh Interval` / `Show Stopped Containers` |
| Test connection / version / update | `testConnection` / `aboutVersion` / `checkForUpdates-about` | `Test Connection` / `Version <v> (<build>)` / `Check for Updates...` |

**Forbidden, always:** Remove container on any container; any action on a card whose name does
not start with `cbqa-` (stop, start, restart: `cbqa-target` only), else stop the step and mark
the run BLOCKED `scope-guard`; Remove Host or Delete Section on anything the run did not create;
Install Update or Skip This Version in a Sparkle dialog (Remind Me Later only); the Launch at
Login toggle; the keyboard shortcut recorder; setting `CONTAINERBAR_HUNT_MODE`; typing a
password or granting any permission.

## QA runtime

Six fixtures, label `com.tookes.containerbar.qa=1`: `cbqa-web` (running, `18080:80` tcp and udp),
`cbqa-logs` (running, prints `cbqa-line-1..3` and `cbqa-err-1`), `cbqa-limited` (running, 256 MiB
limit), `cbqa-target` (running; the only container you may stop, start or restart), `cbqa-tty`
(running, TTY, prints `cbqa-tty-line-1`), `cbqa-stopped` (exited). Baseline: 6 containers,
5 running. `ssh cbqa-ctl <verb>`, verbs `status`, `info`, `reset`, `target-stop`, `api-stop`,
`api-start`; anything else exits 64; `status` exits 2 when Podman is unreachable.
Host entries: `QA Runtime` (SSH, Podman, host `cbqa-tunnel`, user `cbqa-fwd`, remote socket
`/run/cbqa-api/podman.sock`, always the selected host) and `QA Runtime (socket)` (Unix Socket,
Podman, socket `$HOME/qa/containerbar/podman.sock` expanded).

## Evidence

Root: `artifacts/containerbar-qa/runs/<YYYY-MM-DD>-daily-<HHMM>/` (`<run>` below). It holds
`report.md`, `defaults-before.plist`, `assets/<TC-id>/NN-<slug>.png` (one per step, NN from 01,
slug in lower-case words such as `01-status-item.png`), and `assets/<TC-id>.mp4` for exactly
TC-CB-08, 10, 13, 15, 16, 17 (no other case records video; use the `peekaboo` skill's recording
command scoped to the ContainerBar window). Screenshot with
`peekaboo see --app com.tookes.ContainerBar --annotate --path "<run>/assets/<TC-id>/NN-<slug>.png" --json`;
a capture showing more than the app panel or Settings window is cropped (`sips -c`) or deleted.
Command output, dialog text and element lists go into `report.md` verbatim.

## Step 0: preflight

```sh
cd "${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}"
SESSION='cbqa-daily-YYYYMMDD-HHMM'   # from the brief
python3 -B tools/containerbar-qa/cbqa_lane.py preflight --session "$SESSION"
```

`READY` (0): continue. `BLOCKED ci-busy|desktop-busy|restore-failed` (2): no case runs; write
the report with that verdict, post the printed `POST TO` line if any, stop. `NEEDS-NORMALISE` (3):
close the Settings window or press Remind Me Later in the Sparkle dialog, then
`python3 -B tools/containerbar-qa/cbqa_lane.py normalise --token "$TOKEN"`. Copy every `note:` line.

```sh
cd "${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}"
TOKEN='lock-token-from-preflight'; RUN='artifacts/containerbar-qa/runs/YYYY-MM-DD-daily-HHMM'
mkdir -p "$RUN/assets"
ssh cbqa-ctl reset && ssh cbqa-ctl status          # baseline? else wait 60 s, retry once
defaults export com.tookes.ContainerBar "$RUN/defaults-before.plist"
python3 -B tools/containerbar-qa/cbqa_lane.py prefs-drift "$RUN/defaults-before.plist" qa/containerbar/baseline.plist
```

`status` not the baseline after the retry: BLOCKED `qa-runtime-down` (first stderr line in the
notes), no case is FAIL, go to the restore. `drift:` other than `none`: finding "previous run left
state"; do the fallback restore (Restore step 2) before the first case.

## Every case

```sh
cd "${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}"
python3 -B tools/containerbar-qa/cbqa_lane.py case-gate --token "$TOKEN" TC-CB-01
```

`ok`: run it. `BLOCKED ci-busy`: finish the current step, mark this and the rest `blocked ci-busy`,
go to the restore. `BLOCKED time-budget`: the rest `blocked time-budget`, restore.
`BLOCKED time-budget lock-not-owned`: start nothing, touch nothing on the desktop, mark the rest
`blocked time-budget` (note `lock-not-owned`), run `release` (it refuses), record both answers.
Each case: screenshot before and after every action, re-`see` after every click, record PASS, FAIL,
BLOCKED (reason), SKIPPED or known failure (CB id). A video case starts its recording first.

### Runnable today (TC-CB-13, the Sparkle offer from the previous release, is release-brief only)

**TC-CB-01 Installed build is the signed latest release** (shell only).

```sh
APP=/Applications/ContainerBar.app
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"; echo "codesign=$?"
spctl --assess --type execute "$APP"; echo "spctl=$?"
xcrun stapler validate "$APP"; echo "stapler=$?"
codesign -dv --verbose=4 "$APP" 2>&1 | grep '^Authority=' | head -n1
curl -sSf https://api.github.com/repos/michaeltookes/ContainerBar/releases/latest | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])'
curl -sSf https://michaeltookes.github.io/ContainerBar/appcast.xml | grep -o '<sparkle:shortVersionString>[^<]*' | head -n1 | cut -d'>' -f2
curl -sSf https://raw.githubusercontent.com/michaeltookes/homebrew-tap/main/Casks/containerbar.rb | grep -m1 '^ *version '
```

PASS: the three checks exit 0, the first Authority line equals `CBQA_DEVELOPER_ID_AUTHORITY`, and
tag (without `v`) = appcast = cask = installed. Installed differs: FAIL `stale-install`, continue
against the installed build. A signing check fails: FAIL quoting the output, message `QA FAIL`
naming the check, do not launch the app. Versions disagree: `FAIL TC-CB-01` with the four values.

**TC-CB-02 Status item present and named.** If `pgrep -x ContainerBar` has no released PID:
`open /Applications/ContainerBar.app`; within 10 s the status item shows. Then:
`01-status-item.png` (menu bar strip cropped to the item), the item's title and accessibility
value from `menubar list` (value non-empty), `02-panel-open.png` after opening it. No item in 10 s:
FAIL with the last 50 lines of `log show --last 2m --predicate 'process == "ContainerBar"'` and
the newest `~/Library/Logs/DiagnosticReports/ContainerBar-*.ips` file name.
Hunt build checks (recorded under TC-CB-02): the released panel never shows the host `Fixture
Docker` or `fixture log line` text (seeing it is `FAIL P1`: hunt mode in a release, CB-090);
note whether a hunt-build process was running; `defaults read com.tookes.ContainerBar.hunt
SULastCheckTime` should report the key missing (present: finding linked to CB-074).

**Local Network gate (CB-116).** Run it once here: after TC-CB-01 and TC-CB-02 (the app is
installed, verified and running) and before TC-CB-14 and any SSH-dependent case or step.
**Open** when `local-network-grants.log` has a line for the installed release (`developer-id`
covers every release on this Mac): Settings > Connections > `QA Runtime` > Test Connection must
show success, the only accepted proof. `No route to host` or the Local Network message while
`ssh cbqa-ctl status` worked: BLOCKED `local-network-denied`, one line to `CBQA_ALERT_TARGET`, SSH
cases `blocked local-network-denied`. Any other failure: `FAIL TC-CB-03` with the error verbatim,
SSH cases `blocked app-cannot-connect`. **Closed** (no line; the state until CB-116 lands): do not
click Test Connection; every SSH case is `blocked local-network-denied (CB-116)`. The system dialog
"Allow "ContainerBar" to find devices on local networks?" (it can appear at any launch): leave it
untouched, note `local-network-prompt-open`; it alone does not stop the pass (CB-116).

**TC-CB-14 Check for Updates when current.** First
`curl -sSfI https://michaeltookes.github.io/ContainerBar/appcast.xml`; non-zero: `blocked
appcast-unreachable`, capture any Sparkle error text. Settings > About: `01-about.png` (version
and build visible), press Check for Updates, `02-sparkle-result.png`. "You're up to date": PASS,
close the dialog. Newer version offered: note `update-available <v>`, press Remind Me Later,
PASS with note. Button does nothing: finding linked to CB-074. Close Settings.

**TC-CB-08 Settings persist across relaunch** (video). General: `01-general-baseline.png`
(10 seconds, show stopped on); set Refresh Interval to 30 seconds and Show Stopped Containers off,
`02-general-changed.png`; Quit; `open /Applications/ContainerBar.app`; General shows 30 s and off
(`03-after-relaunch.png`); Connections lists `QA Runtime` and `QA Runtime (socket)` with the same
types, `QA Runtime` currently active (`04-connections.png`; a missing host is `FAIL P1`, CB-075).
Dashboard hides `cbqa-stopped`: run it only with the gate open, else that step is
`blocked local-network-denied (CB-116)` and the case verdict comes from the other steps.
Restore: 10 seconds, show stopped on, Quit, relaunch, `05-restored.png`; note the restored values.

**Unix-socket leg (Wednesday and Saturday only; runs with the gate closed: the forward is the
lane's own shell `ssh`, the app only opens a local socket).**
- **TC-CB-12 Missing socket shows a useful error.** `python3 -B tools/containerbar-qa/cbqa_lane.py
  forward-stop`; select `QA Runtime (socket)` (host pill or Settings > Connections > Set as Active
  Host); after one refresh, `01-socket-error.png` and the error text verbatim. PASS: it names the socket or the runtime. "Docker connection not configured": known failure CB-077.
- **TC-CB-11 Unix-socket transport.** `python3 -B tools/containerbar-qa/cbqa_lane.py forward-start`;
  `BLOCKED forward-failed`: case `blocked forward-failed`. `FORWARD-READY`: within one refresh
  interval the panel shows six `cbqa-` cards, Running 5, `cbqa-stopped` stopped, no error banner
  (`01-socket-connected.png`, `02-cards.png`); copy the `forward:` lines into the notes.
- After the leg: `forward-stop`, select `QA Runtime` again (`03-qa-runtime-selected.png`).

### SSH cases: blocked until CB-116 (exact report entry `blocked local-network-denied (CB-116)`)

Run these only with the gate open, selecting `QA Runtime`; read the runtime with `ssh cbqa-ctl status`.
- TC-CB-03 connects: panel opens, connection state names `QA Runtime`, no banner; time to first list.
- TC-CB-04 baseline list: six `cbqa-` cards, Running 5, `cbqa-stopped` stopped.
- TC-CB-05 remote socket at a custom path: host detail shows `cbqa-fwd` and `/run/cbqa-api/podman.sock`; Test Connection green.
- TC-CB-06 ports and memory: one `18080` pill on `cbqa-web`, details list tcp and udp rows; RAM denominator = `ssh cbqa-ctl info` `memTotal` ±0.1 GB (CB-069, CB-079 known).
- TC-CB-07 logs (open with the Logs button, then the `cbqa-logs` row): `cbqa-logs` shows `cbqa-line-1..3`, `cbqa-err-1` in order, each line starting `cbqa-`; `cbqa-tty` shows `cbqa-tty-line-1` (CB-070 known).
- TC-CB-09 external change: `ssh cbqa-ctl reset`, list matches within one interval, icon leaves the refresh glyph.
- TC-CB-10 stop and start `cbqa-target` (video): stopped within 10 s and `status` agrees; Start, running.
- TC-CB-15 restart (video): `startedAt` later within 30 s; no Restart control: `blocked` with the element list, propose a defect (CB-082).
- TC-CB-16 runtime away (video): `ssh cbqa-ctl api-stop`, two intervals, message verbatim, nothing stale shown running; `ssh cbqa-ctl api-start`, six cards back without relaunch (CB-071, CB-077 known texts).
- TC-CB-17 stale stop (video): `ssh cbqa-ctl target-stop`, then Stop in the app before a refresh; banner or no-op, stopped after refresh, no hang; banner text verbatim, dismiss; restart `cbqa-target` with `ssh cbqa-ctl reset`.

## Stop and ask

A Keychain password prompt, a TCC prompt, a Gatekeeper dialog or any system dialog this recipe
does not name (the ContainerBar Local Network dialog above is the only exception): type nothing,
grant nothing, click nothing in it. Take a cropped screenshot, mark the run BLOCKED, post one
line to `CBQA_ALERT_TARGET` asking the owner to act, then go to the restore. App crash or no AX
response for 30 s: `FAIL P1` with the newest `.ips` file name, relaunch once to finish read-only cases.

## Restore and release (always, whatever happened)

```sh
cd "${CBQA_WORKSPACE:-$HOME/.openclaw/workspace}"
zsh tools/containerbar-qa/containerbar-qa-restore.sh   # copy every restore: line; exit 1 = post for help
```

1. The script runs `api-start`, resets fixtures not at baseline, stops the forward by PID,
   removes its socket, deletes the run marker and leaves the `gui-cleanup-pending` flag.
2. In the UI: refresh interval 10 s, Show Stopped Containers on, no run-created section or host,
   `QA Runtime` selected, no Settings window and no Sparkle dialog open, ContainerBar running.
   Fallback when that fails or step 0 found drift: Quit, then
   `defaults import com.tookes.ContainerBar qa/containerbar/baseline.plist`, relaunch, record a finding.
3. Only if step 2 succeeded: `python3 -B tools/containerbar-qa/cbqa_lane.py gui-done`.
   If it failed, leave the flag; the next pass's step 0 quits and relaunches the app.
4. `python3 -B tools/containerbar-qa/cbqa_lane.py release --token "$TOKEN"`. `lock not owned by
   this pass` (exit 1): record it, do nothing else to the lock.
5. Copy the brief's restore checklist into the report, ticked. A failed restore posts to `CBQA_ALERT_TARGET`.

## Report and post

`<run>/report.md`, in this order: header table (date, ContainerBar version and build, machine
`<qa-mini>`, session id, verdict with counts PASS/FAIL/BLOCKED/SKIPPED/known); summary table, one
row per TC id with result and reason; per-case steps with asset paths and verbatim text; **Known
failures** (CB id, fixed-in, case); **Defects and proposed backlog items** (repro steps, expected,
actual, evidence path; a stale recipe goes here); **Run notes** (every `note:`, `forward:` and
`restore:` line, the lock token, restored values, findings, the ticked restore checklist).

Verdict: FAIL if any case failed that is not a known failure; BLOCKED if preflight or the run
stopped on a reason below; else PASS. While the gate is closed the SSH cases are listed as
`blocked local-network-denied (CB-116)` and do not by themselves turn PASS into BLOCKED.

Your final reply is the one Discord message (the cron job announces it to `CBQA_DAILY_TARGET`):
`QA PASS — ContainerBar <version> — <YYYY-MM-DD> <HH:MM>` (or `QA FAIL`, naming the failing TC ids,
or `QA BLOCKED <reason>`), then the counts, the blocked-until-CB-116 count, and the report path.
On FAIL first attach the failing steps' screenshots (videos only under 25 MB) with
`openclaw message send` to `CBQA_DAILY_TARGET`. A failed post is recorded in the run notes as
`post-failed`. On FAIL or BLOCKED end the report with the inbox line for the orchestrator:
`ContainerBar#qa-daily | lucius | qa-found|blocked | artifacts/containerbar-qa/runs/<run> | <one sentence>`.

## Failure vocabulary

| Reason | Meaning |
|---|---|
| `ci-busy` | a runner job on this Mac (`Runner.Worker`, or the runners API says busy) |
| `desktop-busy` | another desktop brief held the lock past T0 + 480 s |
| `restore-failed` | the previous run's marker could not be recovered |
| `qa-runtime-down` | `ssh cbqa-ctl status` failed or not baseline after one retry |
| `local-network-denied` | no positive Test Connection proof of the Local Network grant |
| `app-cannot-connect` | the grant is there, the app still cannot connect (TC-CB-03 FAIL) |
| `forward-failed` | the Unix-socket forward did not produce its socket in 10 s |
| `time-budget` | the case would start after T0 + 1380 s (`lock-not-owned`: hold ran out) |
| `scope-guard` | an action was about to hit a non-`cbqa-target` / non-`cbqa-` card |
| `appcast-unreachable` | the appcast URL did not answer |
| `stale-install` | installed version is not the latest release |
| `runner-api-unavailable`, `windows-normalised`, `previous run left state`, `unexpected update prompt`, `post-failed` | notes and findings, never a verdict |

## Known failures (installed release below `fixed-in` stays quiet)

The orchestrator recomputes `fixed-in` at every release tag (the oldest tag containing the fix's
merge). Installed version at or above `fixed-in`: drop the entry, and the same failure is a FAIL.

| CB id | Case | Expected failure | fixed-in |
|---|---|---|---|
| CB-069 | TC-CB-06 | RAM denominator larger than `memTotal` | unreleased |
| CB-070 | TC-CB-07 | frame-header bytes before `cbqa-` in log lines | unreleased |
| CB-071 | TC-CB-16 | "Invalid response from Docker daemon" | open |
| CB-077 | TC-CB-12, 16 | "Docker connection not configured" | unreleased |
| CB-079 | TC-CB-06 | doubled `18080` pill or port rows | unreleased |
| CB-082 | TC-CB-15 | no Restart control in the dashboard (blocked, not FAIL) | open |
| CB-107 | all | identifiers missing; use label fallbacks | unreleased |
