# Lucius daily QA for ContainerBar — design

Status: proposed (2026-10-14). Companion to the requirements brief `docs/requirements/containerbar-factory-intake.md` (written in parallel; the two are reconciled at merge). This repository is public: every host, user, and address below is a placeholder; the real values live in the QA machine's private configuration, never here.

Placeholders used throughout:

| Placeholder | Meaning |
|---|---|
| `<qa-mini>` | Lucius' Mac mini, the agent/QA machine (also hosts this repo's self-hosted `prowl-qa` runner) |
| `<qa-container-host>` | The homelab Linux container host reached over the LAN |
| `cbqa` | Dedicated, unprivileged Linux user on `<qa-container-host>` that owns every QA fixture |
| `cbqa-tunnel`, `cbqa-ctl` | `~/.ssh/config` host aliases on `<qa-mini>` (see Auth) |
| `<cbqa-uid>` | Numeric UID of `cbqa` (not 1000; that is deliberate, see TC-CB-05) |

## 1. Context

**What exists.**
- The app has two transports to a Docker-compatible API: a local Unix socket (`DockerAPIClientImpl+UnixSocket.swift`, `UnixSocketConnection`) and an SSH tunnel that forwards a remote Unix socket to a local one (`SSHTunnelProcessLauncher`, `/usr/bin/ssh -nNT -L <local.sock>:<remote.sock> user@host` with `BatchMode=yes`, `StrictHostKeyChecking=yes`, `~/.ssh/known_hosts`). TLS is partial. `ContainerRuntime` is `docker` or `podman`; it only changes default socket paths, badges, and copy; the wire API is the same.
- PR-gate QA already exists: Prowl hunts (`.prowl/`, `.github/workflows/prowl-qa.yml`) drive a **hunt-mode** Debug build (`com.tookes.ContainerBar.hunt`, `FixtureDockerAPIClient`, throwaway defaults suite, no Sparkle). Hunts are open-and-assert, never touch a real daemon, and run on the `<qa-mini>` self-hosted runner.
- Release-time QA: `scripts/smoke-launch-mini.sh` verifies codesign/Gatekeeper/staple of the notarized zip on `<qa-mini>` and launches it once.
- Latest release: v2.0.4 (2026-09-12), distributed as `ContainerBar.zip` on GitHub Releases, the Sparkle appcast at `https://michaeltookes.github.io/ContainerBar/appcast.xml`, and the `containerbar` cask in `michaeltookes/tap`.
- On `<qa-mini>` the same operator agent already runs a Sentwise daily deep pass (09:35 America/Chicago, isolated session, `gpt-6-astra`, 1200 s, Peekaboo-driven), a zero-token launchd hourly check, task briefs under `~/.openclaw/workspace/tasks/`, evidence under `~/.openclaw/workspace/artifacts/<app>-qa/runs/`, a desktop lock, and a monitor pause.

**What changes.** A second scheduled desktop pass, for the **released, notarized** ContainerBar against **real** container runtimes, plus a zero-token hourly check, a disposable fixture set on `<qa-container-host>`, a handful of accessibility identifiers in the app, and `docs/qa/test-cases.md` / `docs/qa/seed-data.md` in this repo.

**What stays.** Hunt mode and the Prowl PR gate are unchanged and remain the only QA that runs per pull request. No QA build, no `--qa` flag: the daily pass tests exactly what users install. No container runtime is installed on any Mac (standing rule: no Docker Desktop on the Macs; containers run on the homelab host).

## 2. Container runtime the Mini monitors

### Options weighed

| | A. Podman machine on `<qa-mini>` | B. Rootless Podman as `cbqa` on `<qa-container-host>` over SSH (recommended) | C. The host's system Docker daemon over SSH |
|---|---|---|---|
| App path exercised | Unix socket (genuinely local) | SSH tunnel daily; Unix socket via a forwarded socket on two days a week | SSH tunnel |
| Fits standing rules | **No.** The 2026-10-12 decision puts every container on the homelab host; a Podman VM on a Mac is the same class of thing as Docker Desktop | Yes | Yes, but see safety |
| Blast radius of a wrong click | QA VM only | `cbqa`'s own containers only: a rootless Podman socket cannot see or control the system daemon's services | **Every real service on the host.** Docker socket access is root-equivalent; the app's menu offers Stop/Restart/Remove on all of them |
| Cost on `<qa-mini>` (16 GB, also CI) | 2–4 GB RAM VM, competes with CI | ~0 (one ssh process) | ~0 |
| Independence from the host's pending Docker-vs-Podman choice | Independent | Independent: rootless Podman for one user coexists with whatever system runtime the host runs | Coupled |

**Recommendation: B is the daily default.** It is the only option that is both inside the standing rules and safe by construction: isolation is enforced by the kernel and Podman's user namespace, not by the agent's discipline. It also exercises the riskiest code (SSH tunnel launch, reconnect coordinator, remote Podman socket at a non-default UID).

**How the Unix-socket path is still exercised.** On Wednesday and Saturday the brief opens an SSH stream-local forward on `<qa-mini>`:
`ssh -nNT -o ExitOnForwardFailure=yes -L ~/qa/containerbar/podman.sock:/run/user/<cbqa-uid>/podman/podman.sock cbqa-tunnel` (started by the brief, stopped by its PID at the end of the leg; `<qa-mini>` is the one machine where an agent may stop a process it started, by PID). A second app host of type **Unix Socket (Local)** points at that file. The app then speaks through `UnixSocketConnection` exactly as it would to a local daemon. What this does **not** cover: socket auto-discovery for a local Podman machine and the "runtime not running" error path for a stopped local VM. Those stay covered by unit tests and by `TC-CB-12` (socket file absent) unless Michael amends the 2026-10-12 decision to allow option A (open question Q3).

**Docker runtime coverage.** B serves Docker's API through Podman's compatibility layer. Docker-specific behaviour (log multiplexing CB-070, memory limit reporting CB-069, dual-stack port bindings CB-079) is not guaranteed identical. Phase 1 covers those with unit tests on captured Docker payloads. Phase 2, if Michael approves (Q2), adds a **rootless Docker** daemon for a second unprivileged user (`cbqa-docker`) on the same host, giving a weekly Docker leg with the same isolation property. Option C is rejected outright.

### Fixtures (owned by `homelab-it`)

All fixtures belong to `cbqa`, carry the label `com.tookes.containerbar.qa=1`, use images pinned by digest and pulled once (no daily pulls), and are named `cb-qa-*`:

| Name | Image (pinned) | State after reset | Purpose |
|---|---|---|---|
| `cb-qa-web` | small HTTP server (e.g. `nginx:alpine`) | running, port `18080->80` published | ports rendering, card details |
| `cb-qa-logger` | `busybox` | running, non-TTY, prints `cb-qa-logger tick <n>` every 5 s | logs panel; multiplexed stream framing (CB-070) |
| `cb-qa-toggle` | `busybox` running `sleep infinity` | running | the **only** container QA starts and stops |
| `cb-qa-limited` | `busybox`, `--memory 64m` | running | memory metrics (CB-069) |
| `cb-qa-exited` | `busybox` running `true` | exited (0) | "show stopped containers" setting |

Expected daily baseline: 5 containers, 4 running, 1 exited.

**Provisioning (one-time, `homelab-it`, homelab repo, never this repo):** create `cbqa` (no sudo, no `docker` group); install Podman from the distro; `loginctl enable-linger cbqa`; `systemctl --user enable --now podman.socket` as `cbqa`; install `cb-qa-ctl` (below) in `cbqa`'s home; add two keys to `cbqa`'s `authorized_keys`:

1. **Tunnel key:** `restrict,port-forwarding <key>`. No shell, no PTY, forwarding only. This is the key the app uses.
2. **Control key:** `restrict,command="~/bin/cb-qa-ctl" <key>`. A forced command that reads `SSH_ORIGINAL_COMMAND` and accepts only `status` (JSON list of `cb-qa-*` names and states) and `reset`.

**Reset:** `cb-qa-ctl reset` removes every container with the QA label (`podman rm -f --filter label=com.tookes.containerbar.qa=1`) and recreates the five fixtures from the pinned digests; idempotent; < 20 s. It runs from a `cbqa` systemd user timer at **06:45 America/Chicago** daily and is the first step of every daily pass (via the control key), so a pass that died mid-way never leaves the next one in a bad state. `cb-qa-ctl` never takes arguments beyond the two verbs and never touches anything without the label.

## 3. Components and boundaries

```
 <qa-mini> (macOS, logged-in GUI session, user of the operator agent)
 ┌──────────────────────────────────────────────────────────────────────────┐
 │ OpenClaw cron "ContainerBar daily QA" (07:05 CT) ── brief tasks/…md      │
 │   │  Peekaboo (AX + screenshots)                                         │
 │   ▼                                                                      │
 │ /Applications/ContainerBar.app  (cask install = notarized release zip)   │
 │   │ host "QA Podman (SSH)"            │ host "QA Podman (forwarded socket)"
 │   │ /usr/bin/ssh -L … cbqa-tunnel     │ ~/qa/containerbar/podman.sock     │
 │   │                                   ▲ ssh -L (started by the brief,   │
 │   │                                   │ Wed/Sat only, stopped by PID)   │
 │ launchd com.genkeilabs.containerbar-hourly (zero tokens, < 60 s)         │
 │   ├─ ssh cbqa-ctl status   ├─ GitHub API / appcast / tap   ├─ ps         │
 │ self-hosted runners (actions-runner/_work) ── BLOCK desktop QA if busy   │
 └──────┼───────────────────────────────────┼───────────────────────────────┘
        │ SSH (LAN), tunnel key              │ SSH, control key (forced cmd)
 ┌──────▼───────────────────────────────────▼───────────────────────────────┐
 │ <qa-container-host>                                                      │
 │  user cbqa: rootless Podman socket /run/user/<cbqa-uid>/podman/podman.sock│
 │             cb-qa-web, cb-qa-logger, cb-qa-toggle, cb-qa-limited,        │
 │             cb-qa-exited; cb-qa-ctl; systemd timer 06:45 reset           │
 │  ── isolation boundary (user namespace) ──                               │
 │  system container runtime + real services: never reachable by QA         │
 └──────────────────────────────────────────────────────────────────────────┘
 Outputs: ~/.openclaw/workspace/artifacts/containerbar-qa/runs/<date>/  → one Discord message
```

Ownership: `homelab-it` owns everything on `<qa-container-host>`; the orchestrator owns the brief, cron job, and launchd job on `<qa-mini>` (OpenClaw changes go through the git-tracked workspace); a `builder` owns the repo changes in section 9.

## 4. Data and configuration

No server-side data model. The state that matters:

**App preferences on `<qa-mini>`** (domain `com.tookes.ContainerBar`, keys from `SettingsStore.Keys`): `refreshInterval`, `showStoppedContainers`, `launchAtLogin`, `iconStyle`, `dockerHosts` (JSON data), `selectedHostId`, `containerSections` (JSON data); plus Sparkle's `SUEnableAutomaticChecks`, `SUHasLaunchedBefore`, `SULastCheckTime`.

**QA baseline** (`seed-data.md` documents it; the private plist lives at `~/.openclaw/workspace/qa/containerbar/baseline.plist`, never committed):
- Hosts: `QA Podman (SSH)` — SSH, runtime Podman, host `cbqa-tunnel`, user `cbqa`, port 22, remote socket `/run/user/<cbqa-uid>/podman/podman.sock`, selected by default; `QA Podman (forwarded socket)` — Unix Socket, runtime Podman, socket `~/qa/containerbar/podman.sock` (absolute path).
- `refreshInterval = 30s`, `showStoppedContainers = true`, `launchAtLogin = false`, no sections (one section added and removed by TC-CB-08).
- `SUEnableAutomaticChecks = false`, `SUHasLaunchedBefore = true` (no Sparkle permission prompt or background check interrupts a pass; update checks in QA are always user-initiated).
- The baseline is created once by adding the hosts through the Settings UI (that is also the first full run of TC-CB-05), then exported with `defaults export com.tookes.ContainerBar baseline.plist`.

**Per-run snapshot and rollback.** Step 0 of every pass exports the current domain to `runs/<date>/defaults-before.plist`. The last step quits the app through its own Quit button, re-imports `baseline.plist`, and relaunches. If a pass aborts, the next pass's step 0 notices a diff against the baseline, records it in the report as a finding ("previous run left state"), and restores the baseline before testing.

**App-side migrations.** None for QA. CB-075 introduces a settings schema version; its rollback design is in the ticket notes (section 13) and TC-CB-08 is its regression guard.

## 5. Interfaces and contracts

**SSH aliases on `<qa-mini>` (`~/.ssh/config`, private):**
```
Host cbqa-tunnel
  HostName <qa-container-host>
  User cbqa
  IdentityFile ~/.ssh/cbqa_tunnel_ed25519
  IdentitiesOnly yes
Host cbqa-ctl
  HostName <qa-container-host>
  User cbqa
  IdentityFile ~/.ssh/cbqa_ctl_ed25519
  IdentitiesOnly yes
```
The app's argv ends in `cbqa@cbqa-tunnel` (or `-l cbqa -- cbqa-tunnel` after CB-072), which `ssh` resolves through this config, so no address appears in the app's preferences or screenshots. The host key must be in `~/.ssh/known_hosts` (the app uses `StrictHostKeyChecking=yes`).

**`cb-qa-ctl` contract.** `ssh cbqa-ctl status` → exit 0 and one JSON line `{"containers":[{"name":"cb-qa-web","state":"running"},…]}`; exit 2 if Podman is unreachable. `ssh cbqa-ctl reset` → exit 0 and `{"reset":"ok","containers":5}`; non-zero with a one-line reason otherwise. Any other verb → exit 64.

**Docker-compatible API calls the pass exercises** (through the app, never directly): `GET /_ping`, `GET /info`, `GET /containers/json?all=1`, `GET /containers/{id}/stats?stream=false`, `POST /containers/{id}/stop`, `POST /containers/{id}/start`, `GET /containers/{id}/logs?stdout=1&stderr=1&tail=N`.

**Accessibility contract** (stable identifiers QA selects by; a builder adds the missing ones, section 9). Existing: `openSettings`, `refreshContainers`, `toggleSearch`, `quitApp`, `actionBar-refresh|hosts|logs|settings`, `containerCard-<slug>`, `hostPill-<slug>-<uuid>`, `hostRow-<slug>-<uuid>`, `refreshIntervalPicker`, `aboutVersion`, `testConnection`, `openAddHostSheet`, `addHostSheet`, `confirmAddHost`, `logs-panel-close`, `logs-panel-container-<id>`, `refreshLogs`, `dismissActionError`. Status item: label `ContainerBar` and an accessibility value describing state (`StatusItemController` lines ~101 and ~224) but **no identifier**.

## 6. Auth, privacy, and consent

- **No credentials in the app or the repo.** The app authenticates with the tunnel key through `ssh`'s config; no password, no keychain item. Neither key is ever in this repo, a brief, a report, or Discord. Keys are generated on `<qa-mini>` (`ssh-keygen -t ed25519`, no passphrase, file mode 600) by the orchestrator or `homelab-it`; only public halves travel.
- **Least privilege on the host.** Tunnel key: forwarding only. Control key: two verbs only. `cbqa` has no sudo and no access to the system runtime's socket.
- **What leaves the Mini.** Only the Discord summary and screenshots attached to it. Screenshots are cropped to the app's menu panel or Settings window (Peekaboo window/element capture), never full-screen: the menu bar of `<qa-mini>` also shows Sentwise and other agents' state. The Settings → Connections screenshot shows the alias `cbqa-tunnel`, never an address.
- **Public repo rule.** Daily run evidence is never committed here (the Prowl README explains the same risk for CI artifacts). Story-level QA reports that do land in `docs/qa/runs/` contain text plus cropped app-window screenshots only, reviewed by the orchestrator before commit.
- No end-user consent copy changes: the app sends nothing anywhere new.

## 7. Main sequences

### Daily pass (happy path), 07:05 CT, budget 1200 s

```
cron fires → isolated session reads tasks/<date>-containerbar-daily.md (Environment preamble + this pass)
 0 Preflight (shell, no GUI)
   a pgrep -f 'actions-runner/_work' → any match: report BLOCKED(ci), stop
   b acquire desktop lock (same lock as the Sentwise pass; wait ≤ 5 min) → else BLOCKED(lock)
   c pause the hourly monitors (Sentwise and ContainerBar launchd checks honour the lock)
   d ssh cbqa-ctl reset; ssh cbqa-ctl status == baseline → else BLOCKED(env)
   e defaults export → defaults-before.plist; diff vs baseline (finding if drifted); restore
   f install check: brew upgrade --cask michaeltookes/tap/containerbar (no-op when current);
     codesign --verify --deep --strict, spctl --assess, xcrun stapler validate on /Applications/ContainerBar.app;
     installed CFBundleShortVersionString == latest GitHub release tag == appcast top item == cask version
 1 Launch: if not running, `open -a /Applications/ContainerBar.app`; wait for the status item (identifier
   containerBarStatusItem; until it ships, title/label "ContainerBar" via `peekaboo menubar list`)
 2 Read-only legs (every day): TC-CB-01..04, 06, 07, 09
 3 Mutating legs (every day, fixtures only): TC-CB-10 (stop/start cb-qa-toggle), TC-CB-08 (settings persistence:
   change refresh interval, add/remove a section, Quit via quitApp, relaunch, verify, restore)
 4 Rotating legs: Wed/Sat TC-CB-11 (Unix-socket path via forwarded socket); Mon TC-CB-13 (Sparkle update path)
 5 Restore: Quit via quitApp → defaults import baseline.plist → relaunch (app stays running between passes)
   → stop the forwarded-socket ssh by its PID if started → resume monitors → release lock
 6 Evidence: runs/<date>/report.md + screenshots; one Discord message; inbox line only on FAIL/BLOCKED
```

Every leg re-runs check 0a first; a runner job that starts mid-pass ends the pass with BLOCKED(ci) after the current step, then step 5.

### Failure paths

| Case | Detected by | User-visible (Discord) | Logged | Retry |
|---|---|---|---|---|
| CI job on the Mini's runners | `pgrep -f actions-runner/_work` before each leg | `BLOCKED(ci): <n>/<m> cases not run` | report.md lists unrun cases | none that day; the hourly check does not re-fire it. The orchestrator may fire the job manually once CI is idle |
| Fixture host down / SSH refused | preflight 0d | `BLOCKED(env): fixture host unreachable` | ssh stderr (first line) | one retry after 60 s, then BLOCKED. Product cases are **not** marked FAIL when preflight fails |
| App cannot connect while preflight passed | TC-CB-03 | `FAIL TC-CB-03` + cropped screenshot of the error text | app error text verbatim, the status item's accessibility value | none; this is a product finding for triage |
| Release drift (tag ≠ appcast ≠ cask ≠ installed) | 0f | `FAIL TC-CB-01` with the four versions | versions | none |
| Sparkle shows an update when none is expected | any leg | finding "unexpected update prompt"; dismiss with **Remind Me Later**, never **Skip This Version** (that persists) | dialog text | none |
| App crash or hang | process gone / AX tree unresponsive for 30 s | `FAIL P1` + newest `~/Library/Logs/DiagnosticReports/ContainerBar-*.ips` filename | crash report path (file stays local) | relaunch once to finish read-only legs |
| Pass aborted mid-way | next pass step 0e | finding "previous run left state" | the diff | baseline restored automatically |
| Desktop lock held past 5 min | 0b | `BLOCKED(lock)` | lock holder | none |

## 8. Scheduling

**Daily deep pass.** OpenClaw cron job `ContainerBar daily QA`: `07:05 America/Chicago`, isolated session, model `gpt-6-astra`, timeout 1200 s, announces to the ContainerBar channel (Q4). The Sentwise pass runs 09:35–09:55, so the two are 2 h 10 min apart and both take the desktop lock anyway. 07:05 is chosen because the Mini's runners are rarely busy before the workday's first pushes, the 06:45 fixture reset has finished, and the overnight memory jobs (01:00–03:00) are done. The brief lives at `~/.openclaw/workspace/tasks/<date>-containerbar-daily.md` (the date is the brief's creation date; the job reuses it until replaced) with the standard Environment preamble (machine facts, monitor pause, lock, Peekaboo recipes, evidence paths), and the workspace's AGENTS.md task-brief rule applies.

**Hourly smoke: yes, zero tokens.** A launchd agent `com.genkeilabs.containerbar-hourly` runs a shell script hourly 08:00–20:00. No LLM, no AppleScript (System Events wedges under launchd), no GUI interaction. It exits immediately if the desktop lock is held. Checks, each with a timeout, < 60 s total:
1. Release consistency: latest GitHub release tag (`api.github.com/repos/michaeltookes/ContainerBar/releases/latest`), appcast top `sparkle:shortVersionString`, the cask `version` in the tap, and the installed `CFBundleShortVersionString` all agree.
2. App alive: `pgrep -x ContainerBar` (the app is left running between passes). Its RSS is below 200 MB and its CPU time grew by less than 36 s over the hour (≈1 %), from `ps -o rss=,time=`. This catches leaks and idle wake-up regressions (CB-073).
3. Fixture host: `ssh -o ConnectTimeout=5 cbqa-ctl status` matches the expected names and states, allowing `cb-qa-toggle` to be either running or exited. A mismatch is a host problem, not an app one.
4. Gatekeeper: `spctl --assess` on the installed app (cheap, catches a revoked certificate).

It posts to Discord through the webhook in `~/.openclaw/.env` **only on a state change** (green→red, red→green), plus nothing at all when green. Its log goes to `~/.openclaw/workspace/artifacts/containerbar-qa/hourly.log`, rotated weekly.

**Weekly rotation** so both transports and the update path are covered every week: SSH tunnel every day; forwarded Unix socket Wednesday and Saturday; Sparkle update Monday; and Thursday, if Q2 is approved, the Docker leg against `cbqa-docker`.

## 9. Repo artifacts a builder must add

One builder branch, **"QA hooks"** (app code), plus one docs branch (test cases); both small.

**A. Accessibility identifiers** (no behaviour change; follows the existing `accessibilityIdentifier(prefix:identity:)` slug helper):
1. `StatusItemController` (next to `setAccessibilityLabel("ContainerBar")`, ~line 101): `button.setAccessibilityIdentifier("containerBarStatusItem")`. Keep the label and the state value.
2. `ContainerCardView` quick actions: `containerStop-<slug>` / `containerStart-<slug>` on the two buttons (same slug as `containerCard-<slug>`). They are currently shown only on hover or focus; they must stay in the accessibility tree when visually hidden (use opacity, not conditional removal), which also serves CB-081.
3. Logs panel: the row identifier becomes `logs-panel-container-<slug>` (the container ID is unknown to QA in advance); add `logsPanelText` on the log text view.
4. Dashboard connection state: `connectionStatus` on the header element that shows the connected host or the error banner text (`ActionErrorBanner` keeps `dismissActionError`).
5. Settings: `checkForUpdates-general`, `checkForUpdates-about`, `autoCheckUpdatesToggle`, `showStoppedToggle`, `addSectionButton`, and `sectionRow-<slug>-<uuid>`.
6. Add the new mutating identifiers to `.prowl/config.yml` `forbiddenSelectors` (`containerStop-`, `containerStart-`, `checkForUpdates`, `autoCheckUpdatesToggle`) so PR hunts stay open-and-assert.
7. Unit test: one test per new identifier where a pure helper builds it (slug helpers), following the CB-056 pattern; no ViewInspector.

**B. No QA build and no `--qa` flag.** Not needed: the baseline is preferences plus fixtures, and hunt mode already covers offline QA. Explicitly out of scope.

**C. Sparkle testability.** Nothing beyond CB-074 (the updater is injected, nil in hunt mode, and the button is bound to `canCheckForUpdates`) and the identifiers in A5. The Monday leg needs the previous release's `ContainerBar.zip` to stay downloadable from GitHub Releases (it is; do not delete old releases) and the appcast's latest item to be correct. Release-prep must keep publishing a `sparkle:shortVersionString` the hourly check can parse.

**D. Optional, recommended (separate small item for the BA to file):** bootstrap swift-log to an OSLog handler (subsystem `com.tookes.ContainerBar`, dynamic values `.private` by default, host aliases and container names `.public`). Today no `LoggingSystem.bootstrap` exists, so logs go to stderr and are lost when launched by Launch Services. With it, the pass attaches `log show --predicate 'subsystem == "com.tookes.ContainerBar"' --last 25m` to failures. Not a blocker.

**E. `docs/qa/test-cases.md`** (project-planner format: `### TC-CB-<n> Title`, then **Verifies**, **Preconditions**, **Steps**, **Expected**, **Asset**; IDs fixed once published) and **`docs/qa/seed-data.md`** (section 4's baseline with placeholders, the fixture table, and reset instructions pointing at `homelab-it`). Cases:

| ID | Title | Kind | Expected (abridged) |
|---|---|---|---|
| TC-CB-01 | Installed build is the signed latest release | read-only | codesign/spctl/stapler pass; versions agree (tag, appcast, cask, installed) |
| TC-CB-02 | Status item present and named | read-only | item with id `containerBarStatusItem` / label `ContainerBar`; accessibility value non-empty |
| TC-CB-03 | Connects to the QA host over SSH | read-only | menu opens; `connectionStatus` names `QA Podman (SSH)`; no error banner |
| TC-CB-04 | Lists the fixture baseline | read-only | five `containerCard-cb-qa-*` cards; four running, `cb-qa-exited` shown as exited |
| TC-CB-05 | Remote Podman socket at a non-1000 UID | read-only (setup run: mutating) | host detail shows `/run/user/<cbqa-uid>/podman/podman.sock`; Test Connection green |
| TC-CB-06 | Card details: ports and memory | read-only | `cb-qa-web` shows a single `18080` pill (no doubles, CB-079); `cb-qa-limited` shows `/ 64 MB` and the aggregate is not a multiple of host RAM (CB-069) |
| TC-CB-07 | Logs panel shows clean log lines | read-only | `cb-qa-logger` logs contain `cb-qa-logger tick`; no control bytes or frame-header garbage before lines (CB-070) |
| TC-CB-08 | Settings persist across relaunch | mutating (prefs) | refresh interval change, show-stopped toggle, and one added section survive Quit → relaunch; both QA hosts still present (CB-075 guard); restored after |
| TC-CB-09 | Refresh reflects external change | read-only | after `ssh cbqa-ctl reset`, the card list matches within one refresh interval; icon returns from the refresh glyph (CB-073) |
| TC-CB-10 | Stop and start a fixture | mutating (`cb-qa-toggle` only) | Stop → card exited within 10 s and `cbqa-ctl status` agrees; Start → running; no error banner |
| TC-CB-11 | Unix-socket transport (forwarded) | read-only | with `QA Podman (forwarded socket)` selected, TC-CB-03/04 expectations hold (Wed, Sat) |
| TC-CB-12 | Missing socket shows a useful error | read-only | forwarded-socket host selected with the forward **not** running → error names the socket/runtime, not "not configured" (CB-077) |
| TC-CB-13 | Sparkle offers and installs the latest release | mutating (app bundle) | Mon: previous release zip moved into `/Applications` (current bundle moved to Trash, not `rm`) → Check for Updates → offer shows the latest version → install → relaunch → `aboutVersion` = latest |
| TC-CB-14 | Check for Updates when current | read-only | "You're up to date" dialog; dismiss |

Asset: screenshot per step (cropped to the app), video only for TC-CB-10 and TC-CB-13.

## 10. Non-functional requirements

- **Budget:** daily pass ≤ 1200 s wall clock (target 12 min); hourly ≤ 60 s, zero tokens.
- **Isolation:** QA can mutate only `cb-qa-*` under `cbqa`, enforced by the host. On the Mini it mutates only ContainerBar's preferences domain and its app bundle, and always restores the baseline.
- **Desktop exclusivity:** shared desktop lock with the Sentwise pass; CI check before every leg; the hourly script does no GUI work.
- **Network:** the LAN only; GitHub, the appcast, and the tap for version checks. No pulls from container registries during a pass.
- **Observability:** report.md per run (case table PASS/FAIL/BLOCKED/SKIPPED, versions, durations, findings); `hourly.log`; one Discord message per daily run; inbox line only on FAIL or BLOCKED (`ContainerBar#qa | lucius | qa-found|blocked | artifacts/containerbar-qa/runs/<date> | …`).
- **Evidence layout:** `~/.openclaw/workspace/artifacts/containerbar-qa/runs/<YYYY-MM-DD>[-<leg>]/{report.md, defaults-before.plist, screenshots/TC-CB-<n>-<step>.png, video/TC-CB-<n>.mov}`; retained 30 days.
- **Performance signals tracked over time:** idle CPU/RSS (hourly) and time-to-first-list after launch (daily, TC-CB-03).

## 11. Test strategy hooks

- The planner's TC set is section 9E; every case names its fixture and whether it mutates.
- Seed data: the fixture table and preferences baseline (section 4). The project-planner writes `seed-data.md` from them with placeholders.
- Needs Lucius / a device: all TC-CB cases. Needs `homelab-it` first: the fixtures, `cb-qa-ctl`, the timer, and both keys authorised. Needs a builder first: identifiers A1–A5 (until then QA selects by label and may need hover, which is fragile).
- Unit-test hooks that keep the desktop pass small: SSH argv construction (CB-072), settings decode/backup/migration (CB-075), log demultiplexing on a captured Docker payload (CB-070), memory denominator (CB-069), updater nil in hunt mode (CB-074).
- First-run acceptance for the whole setup: three consecutive green daily passes and one Wednesday and one Monday leg before the orchestrator treats the pass as a gate.

## 12. Trade-offs considered

- **Podman machine on the Mini (A):** simplest for the Unix-socket path, but contradicts the 2026-10-12 decision and costs RAM on a CI machine. Rejected as default; kept as Q3.
- **System Docker over SSH (C):** zero setup, but a root-equivalent key and real services one click away. Rejected.
- **Docker-socket proxy restricting the system daemon to GETs:** read-only safety, but it listens on TCP (the app's TLS path is incomplete) and could not test start/stop. Rejected.
- **A QA build or `--qa` flag:** would make the pass test something users never run, and would duplicate hunt mode. Rejected.
- **An LLM-driven hourly smoke:** the Sentwise precedent spent ~200k tokens per hour reading four indicators. Rejected in favour of launchd shell.
- **Quitting the app after each pass vs. leaving it running:** leaving it running gives a 24/7 soak and the hourly CPU/RSS signal, at the cost of a second third-party item in the Mini's menu bar (Q5).
- **Installing from the zip vs. the cask:** the cask downloads the same notarized zip and is what most users run, so it is the daily path; the Monday leg covers a direct-zip install plus Sparkle.

## 13. Ticket design notes (CB-069..CB-082)

Items that need a design note before a builder starts are below. CB-069, CB-070, CB-078, CB-079, CB-080, CB-081, and CB-082 are self-contained as written: their backlog descriptions already name the fix and the test, and they need only the TC references above (CB-069 → TC-CB-06, CB-070 → TC-CB-07, CB-079 → TC-CB-06, CB-081 shares identifier work with section 9A2).

**CB-072 (SSH argv injection).** Extract a pure `SSHTunnelProcessLauncher.arguments(host:user:port:localSocket:remoteSocket:) -> [String]` and unit-test it. Order: `-nNT`, the existing `-o` options, `-p <port>`, `-l <user>`, `-L <local>:<remote>`, `--`, `<host>`. `-l` replaces `user@host`, so a user value can never be parsed as an option or contain `@` games, and `--` ends option parsing before the host. Validation lives in one function, `SSHTargetValidator`, called from `RemoteHostDraftBuilder` (UI error: "Host and user cannot start with '-' or contain spaces.") and again in `DockerAPIClientImpl.init` (throws the existing invalid-configuration error, so a hand-edited or previously persisted bad host fails safely at connect time with that message rather than launching `ssh`). Rules: non-empty; no leading `-`; no whitespace or control characters; user matches `[A-Za-z0-9._][A-Za-z0-9._-]*`; host is a hostname, an `~/.ssh/config` alias, IPv4, or a bracket-free IPv6 literal. Aliases must keep working, since QA's `cbqa-tunnel` depends on them. Tests: injection strings for both fields, alias accepted, IPv6 accepted, and the argv snapshot. Security-review gate per AGENTS.md.

**CB-074 (Sparkle in hunt mode, DEBUG no-op).** Replace the `UpdaterController.shared` singleton with a protocol `UpdateChecking` (`canCheckForUpdates`, `automaticallyChecksForUpdates`, `checkForUpdates()`). `AppDelegate` constructs exactly one `UpdaterController` when `!HuntMode.isActive`, otherwise nil, and passes it down (an environment value for the SwiftUI panes). The panes render the button only when an updater exists, and bind `.disabled` to `canCheckForUpdates`, observed via KVO on `SPUUpdater.canCheckForUpdates`. In DEBUG (`startingUpdater: false`) the button is disabled with the caption "Updates are disabled in development builds." Remove the redundant `AppDelegate.updaterController`. Add the identifiers in section 9A5 and the `.prowl/config.yml` forbids. Tests: hunt mode creates no updater; with a stub updater whose `canCheckForUpdates` is false, the pane's button-state helper reports disabled. This is the precondition for TC-CB-13/14 being deterministic and for hunts never starting Sparkle on the QA machine.

**CB-075 (settings persistence).** Introduce `settingsSchemaVersion` (absent = 1, new = 2). Load: a nil blob means first run, so seed the local host as today. A blob that fails to decode means: log at `.error`; copy the raw data to `dockerHosts.backup` / `containerSections.backup` (overwrite only if no backup exists, so a second bad launch cannot destroy the first copy); show a one-time non-modal notice in Settings ("Some saved hosts could not be read. A backup was kept."); then seed. Decode element-wise (a lossy array wrapper) so one bad host drops one host, not all. `DockerHost` and `ContainerSection` get custom `init(from:)` with `decodeIfPresent` and defaults for every field added after v1. `MatchType` gets machine raw values (`nameContains`, `nameEquals`, `imageContains`, `labelEquals`, …) and a separate `displayName`; its decoder accepts both the legacy UI-string raw values and the new ones. **Rollback:** v2 sections are written to a new key `containerSections.v2` while the legacy key keeps its last v1 value for one release, so a downgraded app still reads its own format instead of wiping sections (the very bug being fixed). Hosts keep their key because their encoding is unchanged. Remove the legacy key in the release after next, and note that in CHANGELOG. Also fix `.labelEquals` with an empty value (use `split(…, omittingEmptySubsequences: false)` or reject empty values in the editor; see CB-085). Replace the test that enshrines "decode fails silently" with tests for: nil, corrupt blob (backup written, notice flag set), one bad element, legacy MatchType, v1→v2 migration, and downgrade read of the legacy key. TC-CB-08 is the desktop guard.

**CB-076 (status-item menu lifecycle).** Track open state from `NSMenuDelegate`: `menuWillOpen` sets `isMenuOpen = true` and `menuDidClose(_:)` sets it false, and `toggleMenu` uses the flag (drop `highlightedItem`). The delegate methods are called on the main thread, so use `MainActor.assumeIsolated { rebuildMenu() }` in `menuWillOpen` for a synchronous rebuild, not a spawned `Task`. That removes the first-show empty-menu race; verify on `<qa-mini>` with TC-CB-02/03. Any modal (`.remove`'s `NSAlert`) runs only after `menu.cancelTracking()` and a hop to the next main-queue turn, the same as `.viewLogs`. Screen choice: `statusItem.button?.window?.screen ?? NSScreen.main`. A single size authority: `AutoResizingHostingView` exposes `width`/`minHeight`, and `+MenuBuilding` stops re-clamping. Collapsed group state moves into the store keyed by group id (non-persistent unless the BA's story says persist). The status-item identifier from section 9A1 lands in the same branch if the QA-hooks branch has not merged first. Tests: a controller test with a fake menu for toggle-open/close and the modal-after-close ordering.

**CB-071 (transport-neutral errors).** Add `DockerAPIError.connectionClosed` (peer EOF before any response bytes) and `.transportFailed(String)` for non-TLS receive/parse failures, replacing the `.tlsConnectionFailed("…")` misuse on the Unix path. `connectionClosed` is transient in `DockerAPIError+Retry` and marks the transport disconnected so the next request reconnects. Map it through the injected error mapper on `NWConnectionTransport.Config` (the `mapSendFailure` pattern) so each transport keeps its own wording. User copy: "Lost connection to <runtime>. Reconnecting…" for the transient case. This matters for the daily pass because the SSH tunnel and forwarded socket idle for 30 s between refreshes: a regression here shows up as TC-CB-09 failures and as red hourly checks after the host's daemon restarts.

**CB-073 (icon observation loop).** The deployment target is macOS 14, so the `Observations` async sequence is not available. Use a continuation-driven loop: register `withObservationTracking`, and in `onChange` schedule one coalesced main-actor update (a `pendingIconUpdate` flag) that re-registers before reading. No sleep. Inject a clock for the test that asserts the icon leaves the refresh glyph after `isRefreshing` flips false within one turn. Success is visible in the hourly check's idle CPU budget.

**CB-077 (error surfacing).** `initializeFetcher()` returns `Result<Void, Error>`. Both `refresh()` and `performContainerAction` call it when the fetcher is nil and route the error through `userFriendlyConnectionErrorMessage`, never overwriting a specific message with "not configured". The copy must be runtime-aware, since Podman users are told to "start Docker Desktop" today: Docker → "Docker is not running. Start Docker and try again."; Podman local → "Podman is not running. Start the Podman machine and try again."; SSH → "Can't reach <host name> over SSH." plus the first stderr line class (auth / host key / refused). A dropped second action sets `busyContainerIds` feedback ("Already working on <name>") and skips `onMenuReopenRequested`. TC-CB-12 is the desktop guard.

## 14. Risks and open questions

**Risks.**
- **Peekaboo flakiness on menu-bar apps** (Sentwise precedent: positional clicks drift when menu rows change). Mitigation: identifiers in section 9A; QA never clicks by position inside the panel.
- **A second menu-bar item on `<qa-mini>`** may shift the Sentwise recipe's status-item index. Mitigation: both recipes resolve the item by label/identifier from `menubar list` each time, never by index.
- **Podman compat API drift vs. Docker** can produce findings that are not real Docker bugs. Mitigation: the report tags runtime-specific findings; Docker coverage comes in phase 2 (Q2).
- **The app's default Podman socket for local machines** (`~/.local/share/containers/podman/machine/podman.sock`) may not match current Podman releases, which put the API socket under the machine's temporary directory. Not testable without option A. Recorded for the BA as a possible finding to verify against Podman docs.
- **Host maintenance or the pending Docker-vs-Podman change on `<qa-container-host>`** could break the fixtures. Mitigation: rootless `cbqa` is independent of the system runtime; the hourly check reports a red host before the 07:05 pass.
- **The `brew upgrade` step in preflight** changes the installed app on release days. That is intended (it is the install-path test), and it is recorded in report.md.

**Open questions for Michael** (each with the assumption this design proceeds on):
1. **May QA touch the homelab container host at all,** through a dedicated unprivileged `cbqa` user with rootless Podman that cannot see the real services? *Assumed yes.* If no, the only remaining option is a Podman machine on the Mini (Q3).
2. **Docker coverage:** add a rootless Docker daemon for a second QA user (weekly Docker leg), or rely on unit tests with captured Docker payloads? *Assumed: phase 1 Podman only; revisit after your Docker-vs-Podman decision for the host.*
3. **Podman machine on Lucius' Mini:** amend the 2026-10-12 "no containers on the Macs" decision for this one QA VM, to cover local socket discovery and the stopped-runtime error? *Assumed no; the forwarded socket covers the Unix-socket code path.*
4. **Channel and time:** post the daily result to a ContainerBar Discord channel (or #lucius-updates if none exists) at 07:05 CT? *Assumed #lucius-updates until a ContainerBar channel exists; 07:05 CT.*
5. **Leave ContainerBar running on the Mini between passes** (24/7 soak plus hourly CPU/memory checks) next to Sentwise's menu-bar item? *Assumed yes.*

## 15. Story-to-design map

The BA's brief names the stories; this maps the work this design implies so the orchestrator can attach it to them at merge.

| Work | Owner | Design sections | Blocks |
|---|---|---|---|
| Provision `cbqa`, rootless Podman socket, fixtures, `cb-qa-ctl`, 06:45 timer, two restricted keys | homelab-it (homelab repo) | 2, 5, 6 | everything below except the builder branch |
| `<qa-mini>` setup: keys, `~/.ssh/config` aliases, known_hosts, cask install, baseline plist (TC-CB-05 setup run) | orchestrator → Lucius brief | 4, 5 | daily pass |
| QA-hooks branch: identifiers 9A1–A6 | builder | 5, 9A | reliable selectors (the pass can start before, by label) |
| `docs/qa/test-cases.md`, `docs/qa/seed-data.md` | project-planner or builder (docs) | 9E, 4 | daily pass brief |
| Daily cron job and brief | orchestrator | 7, 8, 10 | — |
| Hourly launchd check | orchestrator | 8 | — |
| CB-072, CB-074, CB-075, CB-076, CB-071, CB-073, CB-077 | builder, one branch each | 13 | CB-074 before TC-CB-13/14 count as gates |
| OSLog bootstrap (optional) | builder | 9D | — |
| Docker leg (phase 2, Q2) | homelab-it + orchestrator | 2 | — |
