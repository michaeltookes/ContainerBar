#!/usr/bin/env python3
"""CB-142: make sure the released ContainerBar is running before discovery.

`ensure_running` finds the released app's process (never the hunt build),
launches it with `open -a` when there is none, and waits up to LAUNCH_WAIT_S
for the process. A failed `open` is retried once (error -600 included, after
the old PID has exited); a second failure, or no process in time, ends
`BLOCKED app-launch-failed <rc|timeout|-600>`, never `status-item-not-found`.
"""
from __future__ import annotations

import glob
import os
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

from lane_core import APP_NAME, Lane, read_json, write_json
from lane_discovery import DUMP_FILE, STATE_FILE, find_status_item, released_pids, save_dump

LAUNCH_WAIT_S = 10.0   # released process must exist within 10 s of a successful open
OLD_EXIT_S = 10.0      # before a retry, the old process gets 10 s to exit
POLL_S = 0.5
RELAUNCH_EXIT_S = 30.0  # an explicit relaunch waits this long for the old process (a late quit) before giving up
LOG_FILE = "app-launch-log.txt"
RESTORE_FILE = "app-launch-restore.txt"  # launch failures after the pass already blocked (never the dump or state)
LOG_ARGV = ["log", "show", "--last", "2m", "--predicate", 'process == "%s"' % APP_NAME]


def _open(lane: Lane) -> Tuple[int, str]:
    """`open -a`, stderr folded into the output: LaunchServices writes its error (-600) there."""
    return lane.run(["sh", "-c", 'exec open -a "$1" 2>&1', "sh", lane.app_path], 15)


def _reason(rc: int, out: str) -> str:
    return "timeout" if rc == 124 else ("-600" if "-600" in out else str(rc))


def launch_app(lane: Lane, notes: List[str], old_pids: Sequence[int] = ()) -> Tuple[bool, str]:
    """`open -a` with one retry. (True, "") or (False, rc|timeout|-600). Every lane relaunch uses it."""
    rc, out = _open(lane)
    if rc == 0:
        return True, ""
    first = _reason(rc, out)
    end = lane.clock.now() + OLD_EXIT_S
    while old_pids and set(old_pids) & set(released_pids(lane)) and lane.clock.now() < end:
        lane.clock.sleep(POLL_S)
    notes.append("relaunch: retried after %s" % first)
    rc, out = _open(lane)
    return (True, "") if rc == 0 else (False, _reason(rc, out))


def wait_for_pid(lane: Lane) -> Optional[int]:
    """The released pid within LAUNCH_WAIT_S; probes are capped by the deadline and a late answer is not accepted."""
    end = lane.clock.now() + LAUNCH_WAIT_S
    while True:
        pids = released_pids(lane, end)
        if pids and lane.clock.now() <= end:
            return pids[0]
        if lane.clock.now() >= end:
            return None
        lane.clock.sleep(POLL_S)


def _block(lane: Lane, run_dir: Path, reason: str) -> List[str]:
    """Record a launch failure. A pass that already blocked keeps its state and ax-dump.txt untouched."""
    run_dir.mkdir(parents=True, exist_ok=True)
    state = read_json(run_dir / STATE_FILE)
    first = not (state and state.get("status") == "blocked")
    rc, out = lane.run(LOG_ARGV, 20)
    tail = "\n".join(out.splitlines()[-50:]) + "\n"
    home = os.environ.get("HOME", "")
    ips = sorted(glob.glob(os.path.join(home, "Library/Logs/DiagnosticReports/ContainerBar-*.ips")),
                 key=os.path.getmtime)
    name = os.path.basename(ips[-1]) if ips else "none"
    if first:
        save_dump(lane, run_dir, {"pids": [], "menubar_total": 0, "menubar_matches": 0, "peekaboo": []})
        write_json(run_dir / STATE_FILE, {"status": "blocked", "reason": "app-launch-failed",
                                          "menubar": None, "ax": None})
        (run_dir / LOG_FILE).write_text(tail)
        return ["BLOCKED app-launch-failed %s (ax-dump: %s, log: %s, ips: %s)" % (reason, DUMP_FILE, LOG_FILE, name)]
    with (run_dir / RESTORE_FILE).open("a") as fh:
        fh.write("== restore-time launch failed: %s (ips: %s)\n%s" % (reason, name, tail))
    return ["BLOCKED app-launch-failed %s (earlier block %s kept; see %s)" % (reason, state.get("reason"), RESTORE_FILE)]


def ensure_running(lane: Lane, run_dir: Path) -> Tuple[int, List[str]]:
    """(0, report lines) when the released app runs, else (2, [BLOCKED app-launch-failed ...])."""
    pids = released_pids(lane)
    if pids:
        return 0, ["app-launch: already running pid %d" % pids[0]]
    notes: List[str] = []
    ok, reason = launch_app(lane, notes)
    pid = wait_for_pid(lane) if ok else None
    if pid is None:
        return 2, notes + _block(lane, run_dir, reason if not ok else "timeout")
    return 0, notes + ["app-launch: launched (was not running) pid %d" % pid]


def find_with_launch(lane: Lane, run_dir: Path):
    """CB-142 ahead of discovery. A block already reported this pass is answered by discovery as before."""
    state = read_json(run_dir / STATE_FILE)
    if state and state.get("status") == "blocked":
        return find_status_item(lane, run_dir)
    code, lines = ensure_running(lane, run_dir)
    if code != 0:
        return code, lines, None
    code, more, found = find_status_item(lane, run_dir)
    return code, lines + more, found


def relaunch(lane: Lane, run_dir: Path) -> Tuple[int, List[str]]:
    """Explicit relaunch after a Quit (TC-CB-08, restore fallback): wait for the old process to exit, open, verify a new one.

    The old process gets RELAUNCH_EXIT_S; if it is still there the result is
    `BLOCKED app-launch-failed old-pid-still-running` (no signal is ever sent).
    """
    old = released_pids(lane)
    end = lane.clock.now() + RELAUNCH_EXIT_S
    while old and set(old) & set(released_pids(lane)):
        if lane.clock.now() >= end:
            return 2, _block(lane, run_dir, "old-pid-still-running")
        lane.clock.sleep(POLL_S)
    notes: List[str] = []
    ok, reason = launch_app(lane, notes)
    pid = wait_for_pid(lane) if ok else None
    if pid is None or pid in old:
        return 2, notes + _block(lane, run_dir, reason if not ok else "timeout")
    return 0, notes + ["app-launch: relaunched pid %d" % pid]
