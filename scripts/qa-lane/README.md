# ContainerBar QA lane tooling (CB-105)

Shell and Python tools the agent Mini runs around the daily ContainerBar QA pass:
the schedule's preconditions (CI idle, the shared desktop lock, one deadline per
run), the always-run restore, and the zero-token hourly check. Design:
[`docs/architecture/lucius-daily-qa.md`](../../docs/architecture/lucius-daily-qa.md)
sections 7 and 8; requirements story 6 in
[`docs/requirements/lucius-daily-qa.md`](../../docs/requirements/lucius-daily-qa.md).
The pass itself follows [`brief-template.md`](brief-template.md).

Nothing private lives here. Runner names, Discord targets and the webhook are
read at run time from the workspace (`qa/containerbar/lane.env`, and
`CONTAINERBAR_QA_WEBHOOK` in `~/.openclaw/.env`); both files are parsed, never
sourced.

| File | Role |
|---|---|
| `cbqa_lane.py` | command line: `preflight`, `normalise`, `case-gate`, `restore`, `release`, `forward-start`, `forward-stop`, `prefs-drift`, `ci-busy`, `hourly-checks` |
| `lane_core.py` | paths, private settings, the run deadline, the CI-busy predicate, the fixture baseline |
| `lane_preflight.py` | step 0: CI wait, lock wait, marker recovery with the app quit and relaunched |
| `lane_restore.py` | the no-GUI restore and the SSH-forwarded Unix socket |
| `lane_hourly.py` | the hourly checks and the post-on-change rule |
| `lane_prefs.py` | step 0e preference comparison (decoded JSON, app defaults for missing keys) |
| `containerbar-qa-restore.sh` | restore entry point (`--keep-marker` for step 0 recovery) |
| `containerbar-hourly.sh` | launchd entry point; runs the checks under the shared lock, skips when it is held |
| `com.genkeilabs.containerbar-hourly.plist.template` | launchd agent, hourly at :40 from 08:00 to 20:00 |
| `install.sh` | copies the tools into `<workspace>/tools/containerbar-qa/`, renders and loads the agent, optionally adds the OpenClaw cron job; dry run unless `--apply` |

## Rules the code keeps

- **One deadline per run.** `preflight` records T0 once. The CI wait (rechecked
  every 60 s) and then the lock wait share the budget ending at T0 + 480 s;
  a wait that reaches it reports `ci-busy` if CI was still busy, else
  `desktop-busy`. No case starts after T0 + 1380 s (`case-gate` answers
  `time-budget`, reading the clock again after its CI probes); the last 420 s
  are the restore's. Every CI probe's timeout is capped by the deadline it
  serves; `session.json` is written only once the pass holds the lock, and CI
  is checked again right then (busy releases the lock: `ci-busy`).
- **CI-busy predicate.** Busy if `pgrep -x Runner.Worker` prints a PID, or the
  runners API (`gh api repos/<repo>/actions/runners`) lists one of this host's
  runners (`CBQA_RUNNER_NAMES`) with `busy: true`. An API failure is recorded
  as `runner-api-unavailable` and the process check decides alone.
- **Shared desktop lock.** The same lock directory and tool the Sentwise pass
  uses (`tools/sentwise-qa/device_lock.py`, `artifacts/sentwise-qa/device.lock`).
  `preflight` starts a detached holder under that tool, which heartbeats the
  lock until `release` or the run's outer deadline, whichever comes first.
  Every preflight invocation gets a unique lock token (its `--session` label
  plus a random suffix), used for the holder, the ownership check and the
  release file; `--session` is only the label in reports, so two passes given
  the same label never mistake each other's lock for their own.
  Each run has its own release file (`qa/containerbar/lock-release.<token>`);
  a holder watches only its own, so a contender that gave up keeps its
  cancellation even when the owner releases in between.
- **Marker recovery first.** A marker found under the lock belongs to a run
  that did not finish, whatever its age: the restore runs with
  `--keep-marker`, ContainerBar is quit with `osascript` and relaunched
  (`windows-normalised`), and only then is the old marker replaced. Failure
  keeps the old marker and ends `BLOCKED restore-failed` with one line to
  `#lucius-updates` (`CBQA_ALERT_TARGET`). Whenever the restore deletes the marker (the pass's
  step 5 or the hourly backstop) it leaves `qa/containerbar/gui-cleanup-pending`
  in its place; the pass clears it with `gui-done` after its UI restore, and
  otherwise the next pass's step 0 quits and relaunches the app for that flag
  and clears it only after that succeeds.
- **No signals by name.** Nothing here uses `pkill`, `killall` or `kill` with a
  name or pattern. The only process ever signalled is the SSH forward the
  lane started, by its recorded PID, and only when that PID's complete command
  line is the lane's forward command (compared as the raw line `ps` prints, so
  a socket path with a space still matches). A forward that will not stop blocks a new
  one (`forward-failed`) rather than being orphaned.
- **Hourly check.** No model, no AppleScript, no GUI, under 60 s. Skips while
  the lock is held; skips the app-alive and CPU check while CI is busy; posts
  only when the set of failing checks changes, or when the stale-marker
  backstop (marker older than 31 minutes) ran. The checks and the backstop
  share a 40 s budget, leaving the webhook (8 s) and the state file inside
  the wrapper's 55 s limit; a check not observed this run (out of time, or the
  app check while CI is busy) keeps its previous result; undelivered posts
  and backstop events are retried the next run. The launchd agent carries
  `CBQA_WORKSPACE`, rendered by the installer.

## Private settings (`<workspace>/qa/containerbar/lane.env`)

```
CBQA_RUNNER_NAMES=<runner-1>,<runner-2>
CBQA_ALERT_TARGET=channel:<lucius-updates-id>
CBQA_DAILY_TARGET=channel:<containerbar-channel-id>
```

Optional: `CBQA_RUNNER_REPOS` (default `michaeltookes/ContainerBar,michaeltookes/sentwise`),
`CBQA_WEBHOOK_KEY` (default `CONTAINERBAR_QA_WEBHOOK`).

## Install (orchestrator, on the agent Mini, after merge)

```
scripts/qa-lane/install.sh                      # dry run: prints every action
scripts/qa-lane/install.sh --apply              # tools + launchd agent
scripts/qa-lane/install.sh --apply --with-cron --brief tasks/<date>-containerbar-daily.md
```

The cron job is `ContainerBar daily QA`: `5 7 * * *` America/Chicago, isolated
session, `openai/gpt-6-astra`, 1800 s, announced to `CBQA_DAILY_TARGET`
(the schedule is open question 2; 07:05 daily is the working assumption).

## Tests

`python3 -m unittest discover -s scripts/tests -p 'test_qa_lane*.py'` (CI runs
it in the Swift CI workflow). The tests use a scripted command runner and a
fake clock; the lock-holder and launchd entry-point tests start real
processes against stand-in tools in a temporary directory.
