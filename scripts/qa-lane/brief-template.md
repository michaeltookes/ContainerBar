# ContainerBar daily QA brief (template)

The orchestrator copies this into `<workspace>/tasks/<date>-containerbar-daily.md`,
fills the placeholders privately, and points the `ContainerBar daily QA` cron job
at it. The standing recipe (selectors, cases, evidence layout) is
`<workspace>/CONTAINERBAR_QA.md`; this brief adds the schedule's preconditions,
the restore, and the safety rules (requirements story 6, CB-105, CB-110, CB-112).
`T` below means `<workspace>/tools/containerbar-qa`.

## Environment preamble

- Machine: `<qa-mini>`, logged-in GUI session. CI runners live on this Mac; QA never runs while one has a job.
- Evidence root: `<workspace>/artifacts/containerbar-qa/runs/<YYYY-MM-DD>-daily-<HHMM>/`.
- Session id for this run: `cbqa-daily-<YYYYMMDD>-<HHMM>`.
- **One deadline.** `T/cbqa_lane.py preflight` records T0. CI and lock waits share
  the budget to T0 + 480 s; no case starts after T0 + 1380 s; the rest is for the restore.
  Copy every `note:` line preflight prints into the run notes (the wait end times included).
- **Desktop lock.** Preflight takes the workspace desktop lock the Sentwise pass uses and
  holds it for the whole pass; while it is held the Sentwise and ContainerBar hourly
  checks skip. Do not wrap your own Peekaboo calls in `device_lock.py` (the pass already
  holds the lock; a wrapped call would report busy).
- **Never** `kill`, `pkill` or `killall`. ContainerBar is quit through its own Quit item
  (`quitApp`) or `osascript -e 'quit app "ContainerBar"'`. The only process the run stops is
  the SSH forward it started, and `T/cbqa_lane.py forward-stop` does that by its recorded PID.
- Only the QA runtime is ever targeted (`cbqa-ctl`, `cbqa-tunnel`, the `QA Runtime` hosts).
  No secret, key, address or token goes into the report or Discord.

## Step 0: preflight

1. `python3 -B T/cbqa_lane.py preflight --session <session id>`
   - `READY` (exit 0): continue.
   - `BLOCKED ci-busy` / `BLOCKED desktop-busy` (exit 2): no case runs. Report the run as
     BLOCKED with that reason and stop (the lock was never taken; nothing to restore).
   - `BLOCKED restore-failed` (exit 2): the previous run's marker could not be recovered.
     The tool has kept the old marker and released the lock; post the printed line to
     `#lucius-updates` if it says `POST TO`. Stop.
   - `NEEDS-NORMALISE` (exit 3): ContainerBar would not quit, usually because a Settings
     window or a Sparkle dialog is open. Close it by its accessibility identifier (Settings
     window close button; Sparkle **Remind Me Later**, never Skip or Install), then run
     `python3 -B T/cbqa_lane.py normalise`. `READY`: continue. `BLOCKED restore-failed`:
     stop as above. Record `windows-normalised` in the run notes either way it succeeds.
2. `ssh cbqa-ctl reset`, then `ssh cbqa-ctl status` must match the baseline; else retry once
   after 60 s, else BLOCKED `qa-runtime-down` and go to the restore.
3. `defaults export com.tookes.ContainerBar <run>/defaults-before.plist`, then
   `python3 -B T/cbqa_lane.py prefs-drift <run>/defaults-before.plist <workspace>/qa/containerbar/baseline.plist`.
   Any drift is a finding "previous run left state"; restore it with the fallback below
   before the first case.
4. Install check as the recipe says (verify only on a daily pass).

## Every case

Before each case run `python3 -B T/cbqa_lane.py case-gate <TC-ID>` (no waiting):
- `ok`: run the case.
- `BLOCKED ci-busy`: finish the current step, mark this and every remaining case BLOCKED
  `ci-busy`, go to the restore.
- `BLOCKED time-budget`: mark this and every remaining case `blocked` `time-budget`, go to the restore.

## Unix-socket leg (Wednesday and Saturday: TC-CB-11, TC-CB-12)

- TC-CB-12 first (forward **not** running): `python3 -B T/cbqa_lane.py forward-stop`.
- TC-CB-11: `python3 -B T/cbqa_lane.py forward-start`. It stops any leftover forward by its
  recorded PID after checking its command line, removes the stale socket, starts
  `ssh -nNT -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes -L <socket>:<remote socket> cbqa-tunnel`,
  records its PID, and waits up to 10 s for the socket. `BLOCKED forward-failed`: mark
  TC-CB-11 blocked with that reason.
- After the leg: `python3 -B T/cbqa_lane.py forward-stop`.

## Stop and ask (story 6 AC5)

If a Keychain password prompt, a TCC permission prompt or a Gatekeeper dialog appears
that the recipe does not cover: do not type a password, do not grant anything, do not
click Allow. Take a cropped screenshot, mark the run BLOCKED, post one line to
`#lucius-updates` asking the owner to act, then run the restore.

## Step 5: restore (always, whatever the outcome)

1. `zsh T/containerbar-qa-restore.sh`: api-start, fixtures reset if not at baseline,
   the forward stopped by PID and its socket removed. It prints one `restore:` line per
   action and deletes the run marker last; copy them into the run notes. On failure
   (exit 1) it keeps the marker: post one line to `#lucius-updates` asking for help.
2. In the app, through the UI: baseline settings shown (refresh interval 10 s, Show stopped
   containers on, no run-created section), `QA Runtime` selected, no run-created host entry
   left, no Settings window and no Sparkle dialog open, ContainerBar left running.
   Fallback when the UI restore fails or the previous run aborted: quit through `quitApp`,
   `defaults import com.tookes.ContainerBar <workspace>/qa/containerbar/baseline.plist`,
   relaunch, record it as a finding.
3. `python3 -B T/cbqa_lane.py release` to release the desktop lock.
4. Run notes list every restore action above. A restore that failed posts to
   `#lucius-updates`; the hourly check's backstop (31 minutes) and the next pass's step 0
   will retry the no-GUI part.

## Restore checklist (copy into the report)

- [ ] `cbqa-target` running; `ssh cbqa-ctl status` equals the baseline
- [ ] `ssh cbqa-ctl api-start` ran (always runs; required after any `api-stop`)
- [ ] forward stopped by its recorded PID, socket file removed
- [ ] baseline settings restored through the UI (or fallback import, recorded as a finding)
- [ ] `QA Runtime` selected; no run-created host entries
- [ ] no Sparkle or Settings window open; ContainerBar running
- [ ] run marker deleted (by the restore script)
- [ ] desktop lock released
