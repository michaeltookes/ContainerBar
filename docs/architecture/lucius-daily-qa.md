# Lucius daily QA for ContainerBar — design

Status: proposed (2026-10-14), reconciled with the requirements brief `docs/requirements/lucius-daily-qa.md` (stories US-lucius-daily-qa-1..7, backlog CB-100..CB-106) on the same branch. Where the two differed, the brief's names were adopted (fixtures `cbqa-*`, host entry `QA Runtime`, recipe `CONTAINERBAR_QA.md`, evidence layout, reason codes) and this design's runtime topology was adopted. This repository is public: every host, user, and address below is a placeholder; the real values live in the QA machine's private configuration, never here.

Placeholders used throughout:

| Placeholder | Meaning |
|---|---|
| `<qa-mini>` | Lucius' Mac mini, the agent/QA machine (also hosts this repo's self-hosted `prowl-qa` runner) |
| `<qa-container-host>` | The homelab Linux container host reached over the LAN |
| `cbqa` | Dedicated, unprivileged Linux user on `<qa-container-host>` that owns every QA fixture |
| `cbqa-tunnel`, `cbqa-ctl` | `~/.ssh/config` host aliases on `<qa-mini>` (see Auth) |
| `cbqa-fwd` | Forward-only account on `<qa-container-host>` that the app connects as |
| `<cbqa-uid>`, `<cbqa-fwd-uid>` | Numeric UIDs of the two accounts (used only by probe P5) |

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

**Recommendation: B is the daily default.** It is the only option that is both inside the standing rules and safe by construction: isolation is enforced by the kernel, file permissions and Podman's user namespace, not by the agent's discipline. It also exercises the riskiest code (SSH tunnel launch, reconnect coordinator, a remote Podman socket at a non-default path).

**How the Unix-socket path is still exercised.** On Wednesday and Saturday the brief opens an SSH stream-local forward on `<qa-mini>`:
`ssh -nNT -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes -L "$HOME/qa/containerbar/podman.sock":/run/cbqa-api/podman.sock cbqa-tunnel`, started by the brief and stopped by its recorded PID at the end of the leg (`<qa-mini>` is the one machine where an agent may stop a process it started, by PID). The setup run creates the directory once (`mkdir -p -m 700 "$HOME/qa/containerbar"`). Each time the leg starts it: (1) reads `$HOME/qa/containerbar/forward.pid`; if that PID is alive and `ps -p <pid> -o command=` shows `cbqa-tunnel` and this socket path (a forward this lane left behind), stops that PID; (2) removes a stale socket file with `rm -f`; (3) starts the forward with `StreamLocalBindUnlink=yes` (also set in the `cbqa-tunnel` alias; OpenSSH's default is `no`, which makes a leftover socket file fail the bind) and writes its PID to `forward.pid`; (4) waits up to 10 seconds for the socket file, and otherwise marks the leg's cases `blocked` with reason `forward-failed`. A second app host of type **Unix Socket (Local)** points at that file. The app then speaks through `UnixSocketConnection` exactly as it would to a local daemon. What this does **not** cover: socket auto-discovery for a local Podman machine and the "runtime not running" error path for a stopped local VM. Those stay covered by unit tests and by `TC-CB-12` (socket file absent) unless Michael amends the 2026-10-12 decision to allow option A (open question Q3).

**Docker runtime coverage.** B serves Docker's API through Podman's compatibility layer. Docker-specific behaviour (log multiplexing CB-070, memory limit reporting CB-069, dual-stack port bindings CB-079) is not guaranteed identical. Phase 1 covers those with unit tests on captured Docker payloads. Phase 2, if Michael approves (Q2), adds a **rootless Docker** daemon for a second unprivileged user (`cbqa-docker`) on the same host, giving a weekly Docker leg with the same isolation property. Option C is rejected outright.

### Fixtures (owned by `homelab-it`)

All fixtures belong to `cbqa`, carry the label `com.tookes.containerbar.qa=1`, use images pinned by digest and pulled once (no daily pulls), and are named `cbqa-*`:

| Name | Image (pinned) | State after reset | Purpose |
|---|---|---|---|
| `cbqa-web` | small HTTP server (e.g. `nginx:alpine`) | running, no memory limit, `18080:80/tcp` and `18080:80/udp` published | ports rendering, card details (CB-079) |
| `cbqa-logs` | `busybox` | running, non-TTY, prints `cbqa-line-1`, `cbqa-line-2`, `cbqa-line-3` to stdout and `cbqa-err-1` to stderr at start, then sleeps | logs panel; multiplexed stream framing (CB-070) |
| `cbqa-target` | `busybox` running `sleep infinity` | running | the **only** container QA stops, starts, or restarts |
| `cbqa-limited` | `busybox`, `--memory 256m` | running | memory metrics (CB-069) |
| `cbqa-stopped` | `busybox` running `true` | exited (0) | "show stopped containers" setting |
| `cbqa-tty` | `busybox` with `-t`, prints `cbqa-tty-line-1`, then sleeps | running, TTY | raw (non-multiplexed) log path, CB-070's TTY case |

Expected daily baseline: 6 containers, 5 running, 1 exited. `cbqa-ctl status` lists **all** of `cbqa`'s containers unfiltered, so anything without the prefix is visible (brief story 1 AC2).

**Provisioning (one-time, `homelab-it`, homelab repo, never this repo).** Two unprivileged accounts, neither with sudo, neither in `docker`, and **neither with a systemd user manager** (a lingering user manager would own `/run/user/<uid>/bus` and `/run/user/<uid>/systemd/private`; a holder of a key allowed to forward Unix sockets could forward that bus and call `StartTransientUnit` to run arbitrary programs as that user, and `PermitOpen`/`PermitListen` do not restrict Unix-socket forwards):

- **`cbqa`** owns the containers. `loginctl disable-linger cbqa` (the default; asserted by probe P5). The Podman API runs as a **system** unit, not a user unit: `cbqa-podman.service` with `User=cbqa`, `Group=cbqa`, `RuntimeDirectory=cbqa` (mode 0700, used as `XDG_RUNTIME_DIR=/run/cbqa`), `RuntimeDirectoryPreserve=yes` (otherwise stopping the unit deletes `/run/cbqa`, Podman's runroot, and `api-start` after `api-stop` could not reattach to the still-running fixtures), `UMask=0007`, `ExecStart=podman system service --time=0 unix:///run/cbqa-api/podman.sock`, `KillMode=process` (stopping the API leaves the containers running under conmon), and `Delegate=yes` scoped to this unit's cgroup only, so the rootless runtime can apply `cbqa-limited`'s memory limit; this delegates a cgroup subtree, not a bus. `/run/cbqa-api` is created by `tmpfiles.d` as `0750 cbqa:cbqa`, so the socket is `0660 cbqa:cbqa`. `cbqa`'s `containers.conf` sets `cgroup_manager = "cgroupfs"` and `events_logger = "file"` (nothing needs a user bus). Timers are system units too: `cbqa-reset.timer` (06:45 Central, runs `cbqa-ctl reset` as `cbqa`) and `cbqa-podman-revive.timer` (`OnActiveSec=5min`, `RemainAfterElapse=no`, starts `cbqa-podman.service`; `api-stop` re-arms it with `systemctl restart`, so a timer that elapsed in an earlier outage does not sit active-but-elapsed and ignore the next one). A polkit rule lets `cbqa`, and only `cbqa`, start/stop/restart `cbqa-podman.service` and start or restart `cbqa-podman-revive.timer`; nothing else. Control key in `cbqa`'s `authorized_keys`: `restrict,command="<cbqa-home>/bin/cbqa-ctl" <key>` (absolute path; reads `SSH_ORIGINAL_COMMAND`, accepts only the six verbs in section 5; container verbs use `podman --remote --url unix:///run/cbqa-api/podman.sock`). `sshd_config` `Match User cbqa`: `AllowTcpForwarding no`, `AllowStreamLocalForwarding no`, `AllowAgentForwarding no`, `X11Forwarding no`, `PermitTunnel no`, `PermitTTY no`.
- **`cbqa-fwd`** is the forward-only account the app connects as. Shell `/usr/sbin/nologin` (kept deliberately as a second barrier; `cbqa` keeps `/bin/sh` because its forced command `cbqa-ctl` must run through the account's shell), no linger, member of group `cbqa` only (that is what lets it open `/run/cbqa-api/podman.sock`; `cbqa`'s home and `/run/cbqa` stay `0700`). Tunnel key in its `authorized_keys`: `restrict,port-forwarding,command="/usr/bin/false" <key>`. `restrict` alone does not block shell or exec requests, so the forced command is what makes the key forwarding-only: any session (`ssh cbqa-tunnel <command>`, an interactive login) runs the forced command instead of the requested one, through `nologin`, which prints its account-unavailable message and exits non-zero; the requested command never runs (probe P2). Forwarding still works because a forced command applies only to session channels and the app's `ssh -nNT` opens none; it only requests the `-L` stream-local forward. `sshd_config` `Match User cbqa-fwd`: `AllowTcpForwarding no`, `AllowStreamLocalForwarding local`, `AllowAgentForwarding no`, `X11Forwarding no`, `PermitTunnel no`, `PermitTTY no`.
- **No user manager for either account at SSH login.** `pam_systemd` would otherwise start `user@<uid>.service` (and its bus) for every SSH connection, including `-N` tunnels. In `/etc/pam.d/sshd`, immediately before the `pam_systemd` line: `session [success=1 default=ignore] pam_succeed_if.so quiet user in cbqa:cbqa-fwd`, which skips `pam_systemd` for these two users only.

What `cbqa-fwd` can still reach: any Unix socket its uid/gid may open, which is the Podman API socket plus sockets every local user may connect to (for example the system D-Bus, where polkit gates privileged calls and the one rule above names `cbqa`, not `cbqa-fwd`). That is the same exposure as any unprivileged local account and is accepted. Why not a forced command that execs `socat`/`nc` to the socket with `ssh -W` and no forwarding at all: that removes even this residue, but ContainerBar's SSH transport is a server-side stream-local forward (`ssh -L`), which a forced command does not intercept; switching the app to a stdio transport (`ssh host -- socat - UNIX-CONNECT:<sock>`) is an app change, recorded for the BA as a possible low-priority hardening item, not part of this lane.

**Verification probes** (homelab-it runs them from the Mini after provisioning and records the results; all must hold before CB-100 is done): (P1) the app's exact argv (`ssh -nNT … -L <local.sock>:/run/cbqa-api/podman.sock cbqa-tunnel`) creates the local socket and `curl --unix-socket <local.sock> http://d/_ping` prints `OK`; (P2) `ssh cbqa-tunnel touch /tmp/cbqa-p2-probe` exits non-zero (OpenSSH runs the forced `/usr/bin/false` through the account's shell, `nologin`, which prints its account-unavailable message; that message is accepted) and, on the host, `/tmp/cbqa-p2-probe` does not exist, proving no requested command ran; `ssh cbqa-ctl id` exits 64; (P3) the TCP forward is exercised, not just requested: start `ssh -N -o ExitOnForwardFailure=yes -L 15432:localhost:22 cbqa-tunnel` in the background and record its PID, wait 2 seconds, run `nc -w 5 127.0.0.1 15432 </dev/null`, and assert it prints nothing (an allowed forward would print the host's `SSH-2.0-` banner) and that the ssh process's stderr contains `administratively prohibited`; then stop that recorded PID; (P4) forwarding the host's system runtime socket through `cbqa-tunnel` gives permission denied on use; (P5) no user bus is reachable: with a tunnel open, forwarding `/run/user/<cbqa-uid>/bus`, `/run/user/<cbqa-uid>/systemd/private` and `/run/user/<cbqa-fwd-uid>/bus` each fails on use (no such file), and on the host `/var/lib/systemd/linger/cbqa` and `/var/lib/systemd/linger/cbqa-fwd` do not exist, `systemctl is-active user@<cbqa-uid>.service user@<cbqa-fwd-uid>.service` reports `inactive` for both, and `loginctl list-users` shows neither account while a tunnel is up (with no linger and `pam_systemd` skipped there is no logind user object, so `loginctl show-user` would only error); (P6) two consecutive outage cycles recover: `ssh cbqa-ctl api-stop`, wait up to 6 minutes for the revive timer, `ssh cbqa-ctl status` exits 0 with all fixtures still running and `startedAt` unchanged; repeat once more (the second cycle proves the timer re-arms); then `api-stop` followed at once by `api-start` recovers the same way (proves `/run/cbqa` survived the stop).

**Reset:** `cbqa-ctl reset` removes every container with the QA label (`podman rm -f --filter label=com.tookes.containerbar.qa=1`) and recreates the six fixtures from the pinned digests; idempotent; < 20 s. It runs from the system timer `cbqa-reset.timer` (as `cbqa`) at **06:45 America/Chicago** daily and is the first step of every daily pass (via the control key), so a pass that died mid-way never leaves the next one in a bad state. `cbqa-ctl` takes no arguments beyond its verbs and never touches anything without the label.

## 3. Components and boundaries

```
 <qa-mini> (macOS, logged-in GUI session, user of the operator agent)
 ┌──────────────────────────────────────────────────────────────────────────┐
 │ OpenClaw cron "ContainerBar daily QA" (07:05 CT) ── brief tasks/…md      │
 │   │  Peekaboo (AX + screenshots)                                         │
 │   ▼                                                                      │
 │ /Applications/ContainerBar.app  (cask install = notarized release zip)   │
 │   │ host "QA Runtime" (SSH)           │ host "QA Runtime (socket)"        
 │   │ /usr/bin/ssh -L … cbqa-tunnel     │ ~/qa/containerbar/podman.sock     │
 │   │                                   ▲ ssh -L (started by the brief,   │
 │   │                                   │ Wed/Sat only, stopped by PID)   │
 │ launchd com.genkeilabs.containerbar-hourly (zero tokens, < 60 s)         │
 │   ├─ ssh cbqa-ctl status   ├─ GitHub API / appcast / tap   ├─ ps         │
 │ self-hosted runners (Runner.Worker / API busy) ── BLOCK desktop QA        │
 └──────┼───────────────────────────────────┼───────────────────────────────┘
        │ SSH (LAN), tunnel key              │ SSH, control key (forced cmd)
 ┌──────▼───────────────────────────────────▼───────────────────────────────┐
 │ <qa-container-host>                                                      │
 │  cbqa: rootless Podman API (system unit) /run/cbqa-api/podman.sock; cbqa-fwd│
 │             cbqa-web, cbqa-logs, cbqa-target, cbqa-limited,        │
 │             cbqa-stopped, cbqa-tty; cbqa-ctl; system timer 06:45 reset  │
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
- Hosts: `QA Runtime` — SSH, runtime Podman, host `cbqa-tunnel`, user `cbqa-fwd`, port 22, remote socket `/run/cbqa-api/podman.sock`, selected by default; `QA Runtime (socket)` — Unix Socket, runtime Podman, socket `/Users/<qa-mini-user>/qa/containerbar/podman.sock`. The app does not expand `~` (no tilde expansion anywhere in `Sources/`), so the stored value must be the expanded absolute path: the orchestrator's setup run (TC-CB-05) prints it on the Mini with `echo "$HOME/qa/containerbar/podman.sock"` and types that exact string into the Add Host sheet; the recipe records it, and the forward command uses the same `$HOME`-expanded path so the two always match.
- `refreshInterval = 10s` (TC-CB-08 changes it to 30 s and back), `showStoppedContainers = true`, `launchAtLogin = false`, no sections (one section added and removed by TC-CB-08).
- `SUEnableAutomaticChecks = false`, `SUHasLaunchedBefore = true` (no Sparkle permission prompt or background check interrupts a pass; update checks in QA are always user-initiated).
- The baseline is created once by adding the hosts through the Settings UI (that is also the first full run of TC-CB-05), then exported with `defaults export com.tookes.ContainerBar baseline.plist`.

**Per-run snapshot and rollback.** Step 0 of every pass exports the current domain to `<run>/defaults-before.plist` and compares it with `baseline.plist` on an **allowlist of keys only**: `refreshInterval`, `showStoppedContainers`, `launchAtLogin`, `iconStyle`, `dockerHosts`, `selectedHostId`, `containerSections`, `SUEnableAutomaticChecks`, `SUHasLaunchedBefore`, `SUSkippedVersion` (a Skip click would hide future updates, so its presence is drift). Everything else in the domain is volatile and never compared, in particular `SULastCheckTime` (changes on every update check, including TC-CB-14), `SUUpdateGroupIdentifier`, `SULastProfileSubmissionDate`, window autosave keys (`NSWindow Frame *`), status-item position keys (`NSStatusItem Preferred Position *`, `NSStatusItem Visible*`), and `KeyboardShortcuts_*`. The comparison script prints the allowlisted keys that differ, nothing else. Restore is through the UI (brief story 5 AC2: the pass sets the values back in Settings and relaunches). `defaults import baseline.plist` is the **fallback only**: when step 0 finds drift left by an aborted run, or when the UI restore failed, the pass quits the app through its own Quit button, imports the baseline, relaunches, and records it in the run notes as a finding ("previous run left state").

**App-side migrations.** None for QA. CB-075 introduces a settings schema version; its rollback design is in the ticket notes (section 13) and TC-CB-08 is its regression guard.

## 5. Interfaces and contracts

**SSH aliases on `<qa-mini>` (`~/.ssh/config`, private):**
```
Host cbqa-tunnel
  HostName <qa-container-host>
  User cbqa-fwd
  IdentityFile ~/.ssh/cbqa_tunnel_ed25519
  IdentitiesOnly yes
  StreamLocalBindUnlink yes
Host cbqa-ctl
  HostName <qa-container-host>
  User cbqa
  IdentityFile ~/.ssh/cbqa_ctl_ed25519
  IdentitiesOnly yes
```
The app's argv ends in `-l cbqa-fwd -- cbqa-tunnel` (CB-072's argv shape), which `ssh` resolves through this config, so no address appears in the app's preferences or screenshots. The host key must be in `~/.ssh/known_hosts` (the app uses `StrictHostKeyChecking=yes`).

**`cbqa-ctl` contract.** `ssh cbqa-ctl status` → exit 0 and one JSON line `{"containers":[{"name":"cbqa-web","state":"running"},…]}`; exit 2 if Podman is unreachable. `ssh cbqa-ctl reset` → exit 0 and `{"reset":"ok","containers":6}`; non-zero with a one-line reason otherwise. `status` lines also carry `startedAt` (for the restart check). `ssh cbqa-ctl info` → `{"memTotal":<bytes>,"podmanVersion":"…"}` (the denominator check for CB-069). `ssh cbqa-ctl target-stop` → stops `cbqa-target` outside the app (the stale-state case). `ssh cbqa-ctl api-stop` → re-arms `cbqa-podman-revive.timer` with `systemctl restart` (5 minutes, `RemainAfterElapse=no`), then stops `cbqa-podman.service` (containers keep running under conmon, `KillMode=process`), so an aborted run can never leave the API down; `ssh cbqa-ctl api-start` starts the service again now (idempotent). Both go through the polkit rule in section 2. Any other verb → exit 64. Verbs take no arguments.

**Docker-compatible API calls the pass exercises** (through the app, never directly): `GET /_ping`, `GET /info`, `GET /containers/json?all=1`, `GET /containers/{id}/stats?stream=false`, `POST /containers/{id}/stop`, `POST /containers/{id}/start`, `POST /containers/{id}/restart`, `GET /containers/{id}/logs?stdout=1&stderr=1&tail=N`.

**Accessibility contract** (stable identifiers QA selects by; a builder adds the missing ones, section 9). Existing: `openSettings`, `refreshContainers`, `toggleSearch`, `quitApp`, `actionBar-refresh|hosts|logs|settings`, `containerCard-<slug>`, `hostPill-<slug>-<uuid>`, `hostRow-<slug>-<uuid>`, `refreshIntervalPicker`, `aboutVersion`, `testConnection`, `openAddHostSheet`, `addHostSheet`, `confirmAddHost`, `logs-panel-close`, `logs-panel-container-<id>`, `refreshLogs`, `dismissActionError`. Status item: label `ContainerBar` and an accessibility value describing state (`StatusItemController` lines ~101 and ~224) but **no identifier**.

## 6. Auth, privacy, and consent

- **No credentials in the app or the repo.** The app authenticates with the tunnel key through `ssh`'s config; no password, no keychain item. Neither key is ever in this repo, a brief, a report, or Discord. Keys are generated on `<qa-mini>` (`ssh-keygen -t ed25519`, no passphrase, file mode 600) by the orchestrator or `homelab-it`; only public halves travel.
- **Least privilege on the host.** Tunnel key (account `cbqa-fwd`): Unix-socket forwarding only (forced `/usr/bin/false` for any session, TCP forwarding off, no systemd user manager or bus). Control key (account `cbqa`): the six `cbqa-ctl` verbs only, no forwarding. Neither account has sudo or access to the system runtime's socket. Probes P1–P6 in section 2 verify this.
- **What leaves the Mini.** Only the Discord summary and screenshots attached to it. Screenshots are cropped to the app's menu panel or Settings window (Peekaboo window/element capture), never full-screen: the menu bar of `<qa-mini>` also shows Sentwise and other agents' state. The Settings → Connections screenshot shows the alias `cbqa-tunnel`, never an address.
- **Public repo rule.** Daily run evidence is never committed here (the Prowl README explains the same risk for CI artifacts). Story-level QA reports that do land in `docs/qa/runs/` contain text plus cropped app-window screenshots only, reviewed by the orchestrator before commit.
- No end-user consent copy changes: the app sends nothing anywhere new.
- **macOS Local Network permission (CB-115).** Connections to LAN hosts (the SSH tunnel's `ssh` child and the app's own TLS `NWConnection`) need the Local Network grant; `Distribution/Info.plist` carries `NSLocalNetworkUsageDescription`. When a connection fails with "No route to host", the app resolves the route (`ssh -G`, skipping `ProxyJump`/`ProxyCommand` routes) and runs a short `NWConnection` probe; a path unsatisfied with `localNetworkDenied` maps to the Local Network guidance and an "Open Local Network Settings" button instead of ssh's line, so the address never appears. The daily pass never turns the grant off; the denied state is covered by unit tests and TC-CB-18 (release brief or manual).

## 7. Main sequences

### Daily pass (happy path), 07:05 CT, outer timeout 1800 s

**One deadline per run** (T0 = the moment the session starts): the CI wait and the lock wait share a single 8-minute budget (both end at T0 + 480 s, whichever wait uses it); no new case starts after T0 + 1380 s; the remaining 420 s are reserved for the restore (target under 3 minutes). A case that would start after the cut-off is marked `blocked` with reason `time-budget`. The restore always runs: the pass writes the run marker `~/.openclaw/workspace/qa/containerbar/run-active` (session start time) before step 0 and the restore removes it as its last action; the restore itself is a shell script, `containerbar-qa-restore.sh` in the workspace, which the pass calls in step 5, and which also runs as a backstop (a) in step 0 of the next pass and (b) from the hourly check, whenever the marker is older than 31 minutes (the session was killed by the timeout). Step 0 recovers before it records: after acquiring the desktop lock and **before** writing its own marker, it checks for an existing marker; because it holds the lock, any marker present belongs to a run that did not finish, whatever its age, so it runs `containerbar-qa-restore.sh` first. Only when that succeeds does it write the new session's marker. If the recovery fails, it leaves the old marker in place, writes no new one, ends the run BLOCKED `restore-failed`, and posts one line to `#lucius-updates`, so an unprocessed abort is never overwritten. The hourly backstop takes the same lock while it runs the script. The backstop does everything that needs no GUI: `cbqa-ctl api-start`, `cbqa-ctl reset` if `status` is not the baseline, stopping the recorded forward PID and removing its socket file, and deleting the marker. Restoring ContainerBar's preferences needs the app quit, so that part runs only in the next pass's step 0e (fallback import), never from launchd.

```
cron fires → isolated session reads tasks/<date>-containerbar-daily.md (Environment preamble + this pass)
 0 Preflight (shell, no GUI)
   a CI-idle check (the CI-busy predicate below); while busy, re-check every minute for up to
     10 min → still busy: BLOCKED ci-busy, stop
   b acquire the desktop lock (the same workspace lock the Sentwise daily pass takes, described in the
     brief's Environment preamble); held by another brief: wait up to 10 min → else BLOCKED desktop-busy
   c pause the hourly monitors (the Sentwise and ContainerBar launchd checks skip while the lock is held)
   d ssh cbqa-ctl reset; ssh cbqa-ctl status == baseline → else retry once after 60 s → BLOCKED qa-runtime-down
   e defaults export → defaults-before.plist; diff vs baseline (finding if drifted; fallback restore)
   f install check (daily: verify only; release brief: brew upgrade --cask containerbar, story 3 AC4);
     codesign --verify --deep --strict, spctl --assess, xcrun stapler validate on /Applications/ContainerBar.app;
     installed CFBundleShortVersionString == latest GitHub release tag == appcast top item == cask version
 1 Launch: if not running, `open -a /Applications/ContainerBar.app`; wait for the status item (identifier
   containerBarStatusItem; until it ships, title/label "ContainerBar" via `peekaboo menubar list`)
 2 Read-only legs (every pass): TC-CB-01..04, 06, 07, 09, 14
 3 Mutating legs (every pass, fixtures and prefs only): TC-CB-10 (stop/start cbqa-target), TC-CB-15 (restart),
   TC-CB-17 (stale stop via cbqa-ctl target-stop), TC-CB-16 (api-stop / api-start), TC-CB-08 (settings
   persistence: refresh interval 10 s → 30 s, show-stopped off, Quit via quitApp, relaunch, verify, restore in UI)
 4 Rotating leg: Wed/Sat TC-CB-11 and TC-CB-12 (Unix-socket path via the SSH-forwarded socket)
   Release brief only (orchestrator-fired): TC-CB-13 (Sparkle offer from the previous release, no install),
   cask upgrade and zip checks (story 3 AC4-AC6)
 5 Restore (brief story 6 AC4): cbqa-target running (cbqa-ctl reset if needed); api-start if api-stop ran;
   baseline settings shown in the UI (fallback: defaults import); the forwarded-socket ssh stopped by its
   recorded PID and its socket file removed; selected host back to QA Runtime; no Settings window or Sparkle
   dialog open; ContainerBar left running; resume monitors; release the lock
 6 Evidence: report.md + assets under the evidence root; one Discord message; inbox line only on FAIL/BLOCKED
```

**CI-busy predicate** (the one definition used by step 0a, every case, the hourly check, and the brief's story 6 AC2). CI is busy if **either** holds:
1. `pgrep -x Runner.Worker` prints a PID. The runner's listener spawns one `Runner.Worker` process per job (`Runner.Worker spawnclient …`) and it lives for the whole job, including runner-internal phases (checkout, setup, post-job cleanup) when no child command's arguments mention the work directory. This covers every runner registered on this host, whatever repository or organisation it serves.
2. `gh api repos/michaeltookes/ContainerBar/actions/runners` or `gh api repos/michaeltookes/sentwise/actions/runners` lists any of the runners registered on this host with `"busy": true`. homelab-it knows the Mini's runner names; the recipe keeps them in its private section, and the check matches on those names only. This catches the window between job assignment and the worker process appearing.
If the API call fails (no network, or a token without admin read on the repository), the check records `runner-api-unavailable` in the report and relies on (1) alone; it does not treat the failure as idle evidence for anything else. The earlier predicate `pgrep -f actions-runner/_work` is retired: `pgrep -f` matches argument lists, not working directories, so it misses a job during runner-internal phases.

Every case re-runs check 0a first without waiting: a runner job that starts mid-pass ends the pass after the current step with the remaining cases BLOCKED `ci-busy`, then step 5 runs.

### Failure paths

| Case | Detected by | User-visible (Discord) | Logged | Retry |
|---|---|---|---|---|
| CI job on the Mini's runners | the CI-busy predicate (`pgrep -x Runner.Worker`, or the runners API reports a runner on this host `busy: true`) before the pass (10 min wait) and before each case (no wait) | `BLOCKED ci-busy: <n>/<m> cases not run` | report.md lists unrun cases | none that day; the hourly check does not re-fire it. The orchestrator may fire the job manually once CI is idle |
| Fixture host down / SSH refused / `cbqa-ctl status` exit 2 | preflight 0d | `BLOCKED qa-runtime-down` | ssh stderr (first line) | one retry after 60 s, then BLOCKED. Product cases are **not** marked FAIL when preflight fails |
| App cannot connect while preflight passed | TC-CB-03 | `FAIL TC-CB-03` + cropped screenshot of the error text | app error text verbatim, the status item's accessibility value | none; this is a product finding for triage |
| Release drift (tag ≠ appcast ≠ cask ≠ installed) | 0f | `FAIL TC-CB-01` with the four versions | versions | none |
| Sparkle shows an update when none is expected | any leg | finding "unexpected update prompt"; dismiss with **Remind Me Later**, never **Skip This Version** (that persists) | dialog text | none |
| App crash or hang | process gone / AX tree unresponsive for 30 s | `FAIL P1` + newest `~/Library/Logs/DiagnosticReports/ContainerBar-*.ips` filename | crash report path (file stays local) | relaunch once to finish read-only legs |
| Pass aborted mid-way | next pass step 0e | finding "previous run left state" | the diff | baseline restored automatically |
| Desktop lock held past 10 min | 0b | `BLOCKED desktop-busy` | lock holder | none |
| Action about to hit a non-`cbqa-target` card | every click (brief story 4 AC9) | `BLOCKED scope-guard` | the card name | none |
| Recipe element not found (UI changed) | any step | step `blocked`, recipe named stale (brief story 2 AC5) | `peekaboo see` element list as text | none; never improvise a path |
| System prompt (Keychain, TCC, Gatekeeper) | any step | `BLOCKED` + one line to `#lucius-updates` (brief story 6 AC5) | cropped screenshot | none; never type a password or grant a permission |

## 8. Scheduling

**Frequency is Michael's call (brief open question 2).** Two options are on the table:
- **Recommended: one full pass a day at 07:05 CT, every day, plus the hourly check.** One pass already covers every case; the hourly check catches a crash, a release drift, or a dead fixture host within the hour; a second full pass doubles the model spend and the CI-collision exposure for little new signal, because the released build does not change between 07:05 and 15:00.
- **Brief's assumption: two full passes on weekdays (10:00 and 15:00 CT) and one at 10:00 on weekends, plus the hourly check.** If chosen, move the first pass off 10:00 or accept that it often waits on the Sentwise lock (Sentwise runs 09:35–09:55 and may overrun); 10:15 is the nearest safe slot.
Either way the passes take the same desktop lock as Sentwise and run the same CI-idle check, so they never overlap.

**Daily deep pass.** OpenClaw cron job `ContainerBar daily QA`: `07:05 America/Chicago`, isolated session, model `gpt-6-astra`, timeout 1800 s (see the one-deadline rule in section 7), announces to the ContainerBar channel (Q4). The Sentwise pass runs 09:35–09:55, so the two are 2 h 10 min apart and both take the desktop lock anyway. 07:05 is chosen because the Mini's runners are rarely busy before the workday's first pushes, the 06:45 fixture reset has finished, and the overnight memory jobs (01:00–03:00) are done. The brief lives at `~/.openclaw/workspace/tasks/<date>-containerbar-daily.md` (the date is the brief's creation date; the job reuses it until replaced) with the standard Environment preamble (machine facts, monitor pause, lock, Peekaboo recipes, evidence paths), and points at the standing recipe `~/.openclaw/workspace/CONTAINERBAR_QA.md` (brief story 2), the way the Sentwise briefs point at `SENTWISE_QA.md`. The workspace's AGENTS.md task-brief rule applies.

**Hourly smoke: yes, zero tokens.** A launchd agent `com.genkeilabs.containerbar-hourly` runs a shell script hourly 08:00–20:00. No LLM, no AppleScript (System Events wedges under launchd), no GUI interaction. It exits immediately if the desktop lock is held. It then evaluates the CI-busy predicate (section 7); when CI is busy it records `ci-busy` and skips check 2 (a CI job may replace or relaunch the app, which would read as a crash or a CPU spike), still running checks 1, 3 and 4. Checks, each with a timeout, < 60 s total:
1. Release consistency: latest GitHub release tag (`api.github.com/repos/michaeltookes/ContainerBar/releases/latest`), appcast top `sparkle:shortVersionString`, the cask `version` in the tap, and the installed `CFBundleShortVersionString` all agree.
2. App alive: `pgrep -x ContainerBar` (the app is left running between passes). Its RSS is below 200 MB and its CPU time grew by less than 36 s over the hour (≈1 %), from `ps -o rss=,time=`. This catches leaks and idle wake-up regressions (CB-073).
3. Fixture host: `ssh -o ConnectTimeout=5 cbqa-ctl status` matches the baseline exactly, **including `cbqa-target` running**. The hourly check only runs outside the desktop lock, when no pass is mutating fixtures, so the only valid state is the baseline; an exited `cbqa-target` means a failed or skipped restore and is reported as `fixture-drift`. Any other mismatch is a host problem, not an app one.
5. Backstop: if the run marker is older than 31 minutes, run `containerbar-qa-restore.sh` (section 7) and report `restore-backstop-ran`.
4. Gatekeeper: `spctl --assess` on the installed app (cheap, catches a revoked certificate).

It posts to Discord through the webhook in `~/.openclaw/.env` **only on a state change** (green→red, red→green), plus nothing at all when green. Its log goes to `~/.openclaw/workspace/artifacts/containerbar-qa/hourly.log`, rotated weekly.

**Weekly rotation** so both transports are covered every week: SSH tunnel every pass; the SSH-forwarded Unix socket on Wednesday and Saturday; and Thursday, if Q2 is approved, the Docker leg against `cbqa-docker`. The Sparkle offer-from-previous-release case (TC-CB-13) runs only in the orchestrator-fired release brief, never in a scheduled pass (brief story 3 AC6: daily passes never install).

## 9. Repo artifacts a builder must add

One builder branch, **"QA hooks"** (app code), plus one docs branch (test cases); both small.

**A. Accessibility identifiers** (no behaviour change; follows the existing `accessibilityIdentifier(prefix:identity:)` slug helper):
1. `StatusItemController` (next to `setAccessibilityLabel("ContainerBar")`, ~line 101): `button.setAccessibilityIdentifier("containerBarStatusItem")`. Keep the label and the state value.
2. `ContainerCardView` quick actions: `containerStop-<slug>` / `containerStart-<slug>` on the two buttons (same slug as `containerCard-<slug>`). As built (CB-107 review): both end in the container's short id, `containerStop-<slug>-<short-id>` (first 12 characters of the id, lowercased), because two valid names can share a slug (`Web` and `web`); the recipe selects by the prefix `containerStop-<slug>-`. They are currently shown only on hover or focus; they must stay in the accessibility tree when visually hidden (use opacity, not conditional removal), which also serves CB-081.
3. Logs panel: the row identifier becomes `logs-panel-container-<slug>-<short-id>` (the container ID is unknown to QA in advance, so the recipe selects by the prefix `logs-panel-container-<slug>-`; the short-id suffix keeps rows unique when names share a slug); add `logsPanelText` on the log text view.
4. Dashboard connection state: `connectionStatus` on the header element that shows the connected host or the error banner text (`ActionErrorBanner` keeps `dismissActionError`).
5. Settings: `checkForUpdates-general`, `checkForUpdates-about`, `autoCheckUpdatesToggle`, `showStoppedToggle`, `addSectionButton`, and `sectionRow-<slug>-<uuid>`.
6. Add the new mutating identifiers to `.prowl/config.yml` `forbiddenSelectors` (`containerStop-`, `containerStart-`, `checkForUpdates`, `autoCheckUpdatesToggle`) so PR hunts stay open-and-assert.
7. Unit test: one test per new identifier where a pure helper builds it (slug helpers), following the CB-056 pattern; no ViewInspector.

**B. No QA build and no `--qa` flag.** Not needed: the baseline is preferences plus fixtures, and hunt mode already covers offline QA. Explicitly out of scope.

**C. Sparkle testability.** Nothing beyond CB-074 (the updater is injected, nil in hunt mode, and the button is bound to `canCheckForUpdates`) and the identifiers in A5. The release brief's TC-CB-13 needs the previous release's `ContainerBar.zip` to stay downloadable from GitHub Releases (it is; do not delete old releases) and the appcast's latest item to be correct. Release-prep must keep publishing a `sparkle:shortVersionString` the hourly check can parse.

**D. Optional, recommended (separate small item for the BA to file):** bootstrap swift-log to an OSLog handler (subsystem `com.tookes.ContainerBar`, dynamic values `.private` by default, host aliases and container names `.public`). Today no `LoggingSystem.bootstrap` exists, so logs go to stderr and are lost when launched by Launch Services. With it, the pass attaches `log show --predicate 'subsystem == "com.tookes.ContainerBar"' --last 25m` to failures. Not a blocker.

**E. `docs/qa/test-cases.md`** (project-planner format: `### TC-CB-<n> Title`, then **Verifies**, **Preconditions**, **Steps**, **Expected**, **Asset**; IDs fixed once published) and **`docs/qa/seed-data.md`** (section 4's baseline with placeholders, the fixture table, and reset instructions pointing at `homelab-it`). Cases:

| ID | Title | Kind | Expected (abridged) |
|---|---|---|---|
| TC-CB-01 | Installed build is the signed latest release | read-only | codesign/spctl/stapler pass; versions agree (tag, appcast, cask, installed) |
| TC-CB-02 | Status item present and named | read-only | item with id `containerBarStatusItem` / label `ContainerBar`; accessibility value non-empty |
| TC-CB-03 | Connects to the QA host over SSH | read-only | menu opens; `connectionStatus` names `QA Runtime`; no error banner |
| TC-CB-04 | Lists the fixture baseline | read-only | six `containerCard-cbqa-*` cards; Running pill = 5; `cbqa-stopped` shown as stopped |
| TC-CB-05 | Remote Podman socket at a custom path | read-only (setup run: mutating) | host detail shows user `cbqa-fwd` and remote socket `/run/cbqa-api/podman.sock` (not the runtime's default path); Test Connection green |
| TC-CB-06 | Card details: ports and memory | read-only | `cbqa-web` shows a single `18080` pill (no doubles, CB-079); detail popover lists two rows (tcp, udp); the RAM tile's denominator equals `cbqa-ctl info` `memTotal` ±0.1 GB (CB-069) |
| TC-CB-07 | Logs panel shows clean log lines | read-only | `cbqa-logs` shows `cbqa-line-1..3` and `cbqa-err-1` in order, each line starting exactly with `cbqa-`; `cbqa-tty` shows `cbqa-tty-line-1` unchanged (CB-070) |
| TC-CB-08 | Settings persist across relaunch | mutating (prefs) | refresh interval 10 s → 30 s and show-stopped off survive Quit → relaunch (`cbqa-stopped` hidden); `QA Runtime` and `QA Runtime (socket)` still present, `QA Runtime` selected (CB-075 guard); restored in the UI after |
| TC-CB-09 | Refresh reflects external change | read-only | after `ssh cbqa-ctl reset`, the card list matches within one refresh interval; icon returns from the refresh glyph (CB-073) |
| TC-CB-10 | Stop and start a fixture | mutating (`cbqa-target` only) | Stop → card exited within 10 s and `cbqa-ctl status` agrees; Start → running; no error banner |
| TC-CB-11 | Unix-socket transport (SSH-forwarded socket) | read-only | with `QA Runtime (socket)` selected and the brief's forward running, TC-CB-03/04 expectations hold (Wed, Sat) |
| TC-CB-12 | Missing socket shows a useful error | read-only | forwarded-socket host selected with the forward **not** running → error names the socket/runtime, not "not configured" (CB-077) |
| TC-CB-13 | Sparkle offers the latest release to the previous one | release brief only | installed app quit first; previous release zip extracted into a new temp dir and launched → Settings > About → Check for Updates → offer names the latest version with appcast notes → **Remind Me Later** (no install) → quit → temp dir deleted → installed app relaunched |
| TC-CB-14 | Check for Updates when current | read-only | "You're up to date" dialog; dismiss; newer version advertised → record `update-available <v>`, Remind Me Later, PASS with note |
| TC-CB-15 | Restart a fixture | mutating (`cbqa-target` only) | Restart → `cbqa-ctl status` `startedAt` later than before within 30 s; card running. If the released build exposes no Restart control in the dashboard (CB-082), the step is `blocked` with the element list, not FAIL |
| TC-CB-16 | Runtime goes away and comes back | mutating (`cbqa-ctl api-stop`/`api-start`) | within two refresh intervals a disconnected / not-running message (captured verbatim), no stale container shown as running; after `api-start` the six containers return without relaunch. "Invalid response…" links CB-071, "not configured" links CB-077 |
| TC-CB-17 | Stop on an already-stopped container | mutating (`cbqa-target` only) | after `cbqa-ctl target-stop` and before a refresh, Stop in the app → banner or no-op, card stopped after next refresh, no crash; banner dismissed with `dismissActionError`; `cbqa-target` started again |

Asset: a screenshot per step (cropped to the app) for every case, plus one MP4 video (Peekaboo's recording format) for exactly these cases: TC-CB-08, TC-CB-10, TC-CB-13, TC-CB-15, TC-CB-16, TC-CB-17 (every case that mutates state). No other case records video. TC-CB-13 runs in the release brief, not in scheduled passes. The brief's story 2 AC2 uses the same list.

## 10. Non-functional requirements

- **Budget:** outer timeout 1800 s per pass: shared CI and lock wait ≤ 480 s, last case starts by T0 + 1380 s, 420 s reserved for restore (target pass time 12 min, restore under 3 min); hourly ≤ 60 s, zero tokens.
- **Isolation:** QA can mutate only `cbqa-*` under `cbqa`, enforced by the host. On the Mini it mutates only ContainerBar's preferences domain and its app bundle, and always restores the baseline.
- **Desktop exclusivity:** shared desktop lock with the Sentwise pass (10 min wait, then `desktop-busy`); the CI-busy predicate (section 7: `Runner.Worker` process or a busy runner on this host in the runners API) before the pass (10 min wait, then `ci-busy`) and before every case (no wait); the hourly script does no GUI work.
- **Network:** the LAN only; GitHub, the appcast, and the tap for version checks. No pulls from container registries during a pass.
- **Observability:** report.md per run (case table PASS/FAIL/BLOCKED/SKIPPED, versions, durations, findings); `hourly.log`; one Discord message per daily run; inbox line only on FAIL or BLOCKED (`ContainerBar#qa | lucius | qa-found|blocked | artifacts/containerbar-qa/runs/<date> | …`).
- **Evidence layout (brief section 4 and story 2 AC2):** `~/.openclaw/workspace/artifacts/containerbar-qa/runs/<YYYY-MM-DD>-<kind>-<HHMM>/` with `<kind>` = `daily`, `hourly` or `release`, containing `report.md`, `defaults-before.plist`, `assets/<TC-id>/NN-<slug>.png` for every step, and `assets/<TC-id>.mp4` for the video cases listed in §9E; retained 30 days.
- **Performance signals tracked over time:** idle CPU/RSS (hourly) and time-to-first-list after launch (daily, TC-CB-03).

## 11. Test strategy hooks

- The planner's TC set is section 9E; every case names its fixture and whether it mutates.
- Seed data: the fixture table and preferences baseline (section 4). The project-planner writes `seed-data.md` from them with placeholders.
- Needs Lucius / a device: all TC-CB cases. Needs `homelab-it` first: the fixtures, `cbqa-ctl`, the timer, and both keys authorised. Needs a builder first: identifiers A1–A5 (until then QA selects by label and may need hover, which is fragile).
- Unit-test hooks that keep the desktop pass small: SSH argv construction (CB-072), settings decode/backup/migration (CB-075), log demultiplexing on a captured Docker payload (CB-070), memory denominator (CB-069), updater nil in hunt mode (CB-074).
- First-run acceptance for the whole setup: three consecutive green daily passes including one Wednesday or Saturday Unix-socket leg, and one release brief, before the orchestrator treats the pass as a gate.

## 12. Trade-offs considered

- **Podman machine on the Mini (A):** simplest for the Unix-socket path, but contradicts the 2026-10-12 decision and costs RAM on a CI machine. Rejected as default; kept as Q3.
- **System Docker over SSH (C):** zero setup, but a root-equivalent key and real services one click away. Rejected.
- **Docker-socket proxy restricting the system daemon to GETs:** read-only safety, but it listens on TCP (the app's TLS path is incomplete) and could not test start/stop. Rejected.
- **A QA build or `--qa` flag:** would make the pass test something users never run, and would duplicate hunt mode. Rejected.
- **An LLM-driven hourly smoke:** the Sentwise precedent spent ~200k tokens per hour reading four indicators. Rejected in favour of launchd shell.
- **Quitting the app after each pass vs. leaving it running:** leaving it running gives a 24/7 soak and the hourly CPU/RSS signal, at the cost of a second third-party item in the Mini's menu bar (Q5).
- **Installing from the zip vs. the cask:** the cask downloads the same notarized zip and is what most users run, so it is the release-day upgrade path; the release brief also checks the direct zip and the Sparkle offer (brief story 3 AC4–AC6).

## 13. Ticket design notes (CB-069..CB-082)

Items that need a design note before a builder starts are below: CB-071, CB-072, CB-073, CB-074, CB-075, CB-076, CB-077, CB-078. CB-069, CB-070, CB-079, CB-080, CB-081, and CB-082 are self-contained with the BA's Acceptance blocks; they need only the TC references above (CB-069 → TC-CB-06, CB-070 → TC-CB-07, CB-079 → TC-CB-06, CB-081 shares identifier work with section 9A2). For CB-070 the builder starts from a synthetic multiplexed payload built to the Docker stream format (8-byte header: stream type, three zero bytes, big-endian length); the real `cbqa-logs` capture replaces or joins it once the fixtures exist, and does not block the branch.

**CB-078 (dashboard Add Remote Host drift).** Decision: route the dashboard's **Add Remote Host** to the Settings `AddHostSheet` (the BA's assumption) rather than share a `RemoteHostFormFields` view. One form means CB-072's validation, the remote socket path, the runtime picker, and CB-080's test result live in one place. Mechanics: the dashboard button closes the menu (`closeMenuIfOpen()`), opens Settings on the Connections tab, and presents the sheet. Add a `SettingsRoute` value (`.connections(addHost: true)`) on the settings window controller, so this is not driven by notifications. Delete the dashboard form's own fields and `hostPanelSave` path from `HostPanelView`; the host list and selection in the panel stay. Keep `addRemoteHost` as the button's identifier. Tests: the route helper maps the button to `.connections(addHost: true)`; the existing `AddHostSheet` tests cover the form.

**CB-072 (SSH argv injection).** Extract a pure `SSHTunnelProcessLauncher.arguments(host:user:port:localSocket:remoteSocket:) -> [String]` and unit-test it. Order: `-nNT`, the existing `-o` options, `-p <port>`, `-l <user>`, `-L <local>:<remote>`, `--`, `<host>`. `-l` replaces `user@host`, so a user value can never be parsed as an option or contain `@` games, and `--` ends option parsing before the host. Validation lives in one function, `SSHTargetValidator`, called from `RemoteHostDraftBuilder` (UI error: "Host and user cannot start with '-' or contain spaces.") and again in `DockerAPIClientImpl.init` (throws the existing invalid-configuration error, so a hand-edited or previously persisted bad host fails safely at connect time with that message rather than launching `ssh`). Rules: non-empty; no leading `-`; no whitespace or control characters; user matches `[A-Za-z0-9._][A-Za-z0-9._-]*`; host is a hostname, an `~/.ssh/config` alias, IPv4, or a bracket-free IPv6 literal. Aliases must keep working, since QA's `cbqa-tunnel` depends on them. Tests: injection strings for both fields, alias accepted, IPv6 accepted, and the argv snapshot. Security-review gate per AGENTS.md.

**CB-074 (Sparkle in hunt mode, DEBUG no-op).** Replace the `UpdaterController.shared` singleton with a protocol `UpdateChecking` (`canCheckForUpdates`, `automaticallyChecksForUpdates`, `checkForUpdates()`). `AppDelegate` constructs exactly one `UpdaterController` when `!HuntMode.isActive`, otherwise nil, and passes it down (an environment value for the SwiftUI panes). The panes render the button only when an updater exists, and bind `.disabled` to `canCheckForUpdates`, observed via KVO on `SPUUpdater.canCheckForUpdates`. In DEBUG (`startingUpdater: false`) the button is disabled with the caption "Updates are disabled in development builds." Remove the redundant `AppDelegate.updaterController`. Add the identifiers in section 9A5 and the `.prowl/config.yml` forbids. Tests: hunt mode creates no updater; with a stub updater whose `canCheckForUpdates` is false, the pane's button-state helper reports disabled. This is the precondition for TC-CB-13/14 being deterministic and for hunts never starting Sparkle on the QA machine.

**CB-075 (settings persistence).** Introduce `settingsSchemaVersion` (absent = 1, new = 2). Load: a nil blob means first run, so seed the local host as today. A blob that fails to decode means: log at `.error`; copy the raw data to `dockerHosts.backup` / `containerSections.backup` (overwrite only if no backup exists, so a second bad launch cannot destroy the first copy); show a one-time non-modal notice in Settings ("Some saved hosts could not be read. A backup was kept."); then seed. Decode element-wise (a lossy array wrapper) so one bad host drops one host, not all. `DockerHost` and `ContainerSection` get custom `init(from:)` with `decodeIfPresent` and defaults for every field added after v1. `MatchType` gets machine raw values (`nameContains`, `nameEquals`, `imageContains`, `labelEquals`, …) and a separate `displayName`; its decoder accepts both the legacy UI-string raw values and the new ones. **Rollback:** v2 sections are written to a new key `containerSections.v2` while the legacy key keeps its last v1 value for one release, so a downgraded app still reads its own format instead of wiping sections (the very bug being fixed). Hosts keep their key because their encoding is unchanged. Remove the legacy key in the release after next, and note that in CHANGELOG. Also fix `.labelEquals` with an empty value (use `split(…, omittingEmptySubsequences: false)` or reject empty values in the editor; see CB-085). Replace the test that enshrines "decode fails silently" with tests for: nil, corrupt blob (backup written, notice flag set), one bad element, legacy MatchType, v1→v2 migration, and downgrade read of the legacy key. TC-CB-08 is the desktop guard.

**CB-076 (status-item menu lifecycle).** Track open state from `NSMenuDelegate`: `menuWillOpen` sets `isMenuOpen = true` and `menuDidClose(_:)` sets it false, and `toggleMenu` uses the flag (drop `highlightedItem`). The delegate methods are called on the main thread, so use `MainActor.assumeIsolated { rebuildMenu() }` in `menuWillOpen` for a synchronous rebuild, not a spawned `Task`. That removes the first-show empty-menu race; verify on `<qa-mini>` with TC-CB-02/03. Any modal (`.remove`'s `NSAlert`) runs only after `menu.cancelTracking()` and a hop to the next main-queue turn, the same as `.viewLogs`. Screen choice: `statusItem.button?.window?.screen ?? NSScreen.main`. A single size authority: `AutoResizingHostingView` exposes `width`/`minHeight`, and `+MenuBuilding` stops re-clamping. Collapsed group state moves into the store keyed by group id (non-persistent unless the BA's story says persist). The status-item identifier from section 9A1 lands in the same branch if the QA-hooks branch has not merged first. Tests: a controller test with a fake menu for toggle-open/close and the modal-after-close ordering.

**CB-071 (transport-neutral errors).** Add `DockerAPIError.connectionClosed` (peer EOF before any response bytes) and `.transportFailed(String)` for non-TLS receive/parse failures, replacing the `.tlsConnectionFailed("…")` misuse on the Unix path. `connectionClosed` is transient in `DockerAPIError+Retry` and marks the transport disconnected so the next request reconnects. Map it through the injected error mapper on `NWConnectionTransport.Config` (the `mapSendFailure` pattern) so each transport keeps its own wording. User copy: "Lost connection to <runtime>. Reconnecting…" for the transient case. This matters for the daily pass because the SSH tunnel and forwarded socket sit idle between refreshes: a regression here shows up as TC-CB-09 failures and as red hourly checks after the host's daemon restarts.

**CB-073 (icon observation loop).** The deployment target is macOS 14, so the `Observations` async sequence is not available. Use a continuation-driven loop: register `withObservationTracking`, and in `onChange` schedule one coalesced main-actor update (a `pendingIconUpdate` flag) that re-registers before reading. No sleep. Inject a clock for the test that asserts the icon leaves the refresh glyph after `isRefreshing` flips false within one turn. Success is visible in the hourly check's idle CPU budget.

**CB-077 (error surfacing).** `initializeFetcher()` returns `Result<Void, Error>`. Both `refresh()` and `performContainerAction` call it when the fetcher is nil and route the error through `userFriendlyConnectionErrorMessage`, never overwriting a specific message with "not configured". The copy must be runtime-aware, since Podman users are told to "start Docker Desktop" today: Docker → "Docker is not running. Start Docker and try again."; Podman local → "Podman is not running. Start the Podman machine and try again."; SSH → "Can't reach <host name> over SSH." plus the first stderr line class (auth / host key / refused). A dropped second action sets `busyContainerIds` feedback ("Already working on <name>") and skips `onMenuReopenRequested`. TC-CB-12 is the desktop guard.

## 14. Risks and open questions

**Risks.**
- **Peekaboo flakiness on menu-bar apps** (Sentwise precedent: positional clicks drift when menu rows change). Mitigation: identifiers in section 9A; QA never clicks by position inside the panel.
- **A second menu-bar item on `<qa-mini>`** may shift the Sentwise recipe's status-item index. Mitigation: both recipes resolve the item by label/identifier from `menubar list` each time, never by index.
- **Podman compat API drift vs. Docker** can produce findings that are not real Docker bugs. Mitigation: the report tags runtime-specific findings; Docker coverage comes in phase 2 (Q2).
- **The app's default Podman socket for local machines** (`~/.local/share/containers/podman/machine/podman.sock`) may not match current Podman releases, which put the API socket under the machine's temporary directory. Not testable without option A. Recorded for the BA as a possible finding to verify against Podman docs.
- **Host maintenance or the pending Docker-vs-Podman change on `<qa-container-host>`** could break the fixtures. Mitigation: rootless `cbqa` is independent of the system runtime; the hourly check reports a red host before the 07:05 pass.
- **The `brew upgrade` step in the release brief** changes the installed app. That is intended (it is the install-path test), and it is recorded in report.md.
- **`log show --predicate 'process == "ContainerBar"'`** (used by the brief's launch-failure and CB-079 checks) sees only system and SwiftUI messages until the optional OSLog bootstrap (9D) ships; the app's own swift-log output is not in it. The SwiftUI duplicate-ID warning CB-079 counts is a system message, so that check works today.

**Open questions for Michael** (each with the assumption this design proceeds on):
1. **May QA touch the homelab container host at all,** through a dedicated unprivileged `cbqa` user with rootless Podman that cannot see the real services? *Assumed yes.* If no, the only remaining option is a Podman machine on the Mini (Q3).
2. **Docker coverage:** add a rootless Docker daemon for a second QA user (weekly Docker leg), or rely on unit tests with captured Docker payloads? *Assumed: phase 1 Podman only; revisit after your Docker-vs-Podman decision for the host.*
3. **Podman machine on Lucius' Mini:** amend the 2026-10-12 "no containers on the Macs" decision for this one QA VM, to cover local socket discovery and the stopped-runtime error? *Assumed no; the forwarded socket covers the Unix-socket code path.*
4. **Frequency and channel:** one full pass at 07:05 CT every day (recommended), or the brief's two weekday passes (10:00 and 15:00 CT, moved to 10:15 and 15:00) and one at weekends; results to a new private `#containerbar` channel? *Assumed one pass at 07:05 CT; `#lucius-updates` until `#containerbar` exists.*
5. **Leave ContainerBar running on the Mini between passes** (24/7 soak plus hourly CPU/memory checks) next to Sentwise's menu-bar item? *Assumed yes.*

## 15. Story-to-design map

Stories are in `docs/requirements/lucius-daily-qa.md`; their technical tasks are written under each story there.

| Work | Owner | Design sections | Blocks |
|---|---|---|---|
| CB-100: provision `cbqa`, rootless Podman socket, six fixtures, `cbqa-ctl`, 06:45 timer, two restricted keys | homelab-it (homelab repo) | 2, 5, 6 | everything below except the builder branches |
| CB-100/CB-101: `<qa-mini>` setup: keys, `~/.ssh/config` aliases, known_hosts, both host entries, Sparkle prefs, baseline plist (TC-CB-05 setup run); `CONTAINERBAR_QA.md` recipe | orchestrator → Lucius brief | 4, 5 | daily pass |
| QA-hooks branch: identifiers 9A1–A6 | builder | 5, 9A | reliable selectors (the pass can start before, by label) |
| CB-101 task: `docs/qa/test-cases.md`, `docs/qa/seed-data.md` | project-planner or builder (docs) | 9E, 4 | daily pass brief |
| CB-102..CB-104: install, dashboard, settings cases | Lucius via the brief | 7, 9E | — |
| CB-105: cron job(s), brief, CI-idle check, lock, restore; hourly launchd check | orchestrator | 7, 8, 10 | — |
| CB-106: report, Discord, inbox, defect intake | Lucius, orchestrator, BA | 10 | — |
| CB-071, CB-072, CB-073, CB-074, CB-075, CB-076, CB-077, CB-078 | builder, branches as the backlog's Acceptance blocks split them | 13 | CB-074 before TC-CB-13/14 count as gates |
| QA-hooks identifiers (new item, BA to file) | builder | 9A | — |
| OSLog bootstrap (optional) | builder | 9D | — |
| Docker leg (phase 2, Q2) | homelab-it + orchestrator | 2 | — |
