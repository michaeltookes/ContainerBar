"""Step 0 of the ContainerBar daily pass (CB-105, CB-110, CB-112).

preflight():
  a  CI wait: recheck the CI-busy predicate every minute until T0 + 480 s,
     every probe's timeout capped by that deadline; still busy -> BLOCKED
     ci-busy (the lock wait never starts).
  b  lock wait with whatever is left of the same budget, never past it ->
     BLOCKED desktop-busy. The lock is the workspace desktop lock the Sentwise
     pass uses (tools/sentwise-qa/device_lock.py); a detached holder keeps it,
     with heartbeats, until release() or the run's outer deadline. Only now is
     session.json written (a waiting pass never touches the holder's), and CI
     is checked once more: busy -> release the lock, BLOCKED ci-busy.
  0  marker recovery under the lock: any marker present belongs to a run that
     did not finish, so containerbar-qa-restore.sh runs with --keep-marker
     (a gui-cleanup-pending flag left by the hourly backstop needs only the
     GUI part below);
     then ContainerBar is quit (osascript, never a signal) and relaunched to
     close any Settings window or Sparkle dialog (windows-normalised); only
     then is the old marker deleted and the new one written. Failure keeps
     the old marker, releases the lock and ends BLOCKED restore-failed with
     one line to #lucius-updates.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from typing import Callable, Dict, List, Optional

from lane_core import (APP_NAME, CI_RECHECK_S, LOCK_RECHECK_S, Lane, ci_busy, load_session,
                       new_session, publish_session, read_json, write_json)
from lane_restore import restore

READY, BLOCKED, NEEDS_NORMALISE = "ready", "blocked", "needs-normalise"
RECHECK_BUDGET_S = 25  # the CI recheck right after the lock is acquired
HERE = os.path.dirname(os.path.abspath(__file__))


class Holder:
    """A detached device_lock.py process holding the desktop lock for us."""

    def __init__(self, proc: subprocess.Popen):
        self.proc = proc
        self.pid = proc.pid

    def poll(self) -> Optional[int]:
        return self.proc.poll()


def spawn_holder(lane: Lane, run_id: str, timeout_s: float) -> Holder:
    log = lane.artifacts / "lock-holder.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    argv = [lane.python, "-B", str(lane.lock_tool), "--lock", str(lane.lock_dir),
            "--run", run_id, "--session", run_id, "--job", "containerbar-daily-qa",
            "--timeout", str(int(max(timeout_s, 60))), "--grace", "2", "--",
            lane.python, "-B", os.path.join(HERE, "cbqa_lane.py"), "hold", "--run", run_id,
            "--release-file", str(lane.release_file),
            "--until", str(int(lane.clock.now() + max(timeout_s, 60)))]
    with open(str(log), "a") as out:
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=out,
                                start_new_session=True)
    return Holder(proc)


def lock_owner_run(lane: Lane) -> Optional[str]:
    owner = read_json(lane.lock_dir / "owner.json") or {}
    run = owner.get("run")
    return run if isinstance(run, str) else None


def notify(lane: Lane, text: str) -> None:
    """One line to #lucius-updates; printed for the agent when no target is set."""
    target = lane.setting("CBQA_ALERT_TARGET")
    if target:
        rc, _ = lane.run(["openclaw", "message", "send", "--channel", "discord",
                          "--target", target, "-m", text], 30)
        if rc == 0:
            return
    print("POST TO #lucius-updates: %s" % text)


def _stamp(lane: Lane, session: Dict[str, object]) -> str:
    return "T0+%ds" % int(lane.clock.now() - float(session["t0"]))


def acquire_lock(lane: Lane, session: Dict[str, object], notes: List[str],
                 spawn: Callable[[Lane, str, float], Holder]) -> bool:
    """Wait for the shared lock until the wait deadline, never past it.

    On giving up, a holder that may still acquire later is told to let go at
    once (the release file names this run), so a late acquisition never keeps
    the desktop.
    """
    run_id = str(session["session"])
    deadline = float(session["wait_deadline"])
    holder: Optional[Holder] = None
    spawned = False
    while lane.clock.now() < deadline:
        if holder is None:
            holder = spawn(lane, run_id, float(session["outer_deadline"]) - lane.clock.now())
            spawned = True
        while lane.clock.now() < deadline:
            if lock_owner_run(lane) == run_id:
                session["holder_pid"] = holder.pid
                return True
            if holder.poll() is not None:
                break
            lane.clock.sleep(0.5)
        code = holder.poll()
        if code is None:
            break  # still waiting for the lock at the deadline
        notes.append("lock busy (holder exit %s) at %s" % (code, _stamp(lane, session)))
        holder = None
        if lane.clock.now() + LOCK_RECHECK_S > deadline:
            break
        lane.clock.sleep(LOCK_RECHECK_S)
    if spawned:
        _write_release(lane, run_id)
    return False


def _write_release(lane: Lane, run_id: str) -> None:
    lane.release_file.parent.mkdir(parents=True, exist_ok=True)
    lane.release_file.write_text(run_id)


def release_lock(lane: Lane, run_id: Optional[str] = None) -> bool:
    if run_id is None:
        session = load_session(lane) or {}
        run_id = str(session.get("session", ""))
    if lock_owner_run(lane) != run_id:
        return True
    _write_release(lane, run_id)
    for _ in range(20):
        if lock_owner_run(lane) != run_id:
            break
        lane.clock.sleep(0.5)
    released = lock_owner_run(lane) != run_id
    if released:
        try:
            lane.release_file.unlink()
        except FileNotFoundError:
            pass
    return released


def hold(lane: Lane, run_id: str, release_file: Optional[str] = None,
         until: Optional[float] = None) -> int:
    """Child of device_lock.py: keep running until release() names this run.

    The release file and the stop time come from the parent's argv, so the
    holder never depends on its own environment; it exits by itself at the
    run's outer deadline even if release() is never called.
    """
    path = Path(release_file) if release_file else lane.release_file
    while until is None or lane.clock.now() < until:
        try:
            if path.read_text().strip() == run_id:
                return 0
        except OSError:
            pass
        lane.clock.sleep(1)
    return 0


def pgrep_app(lane: Lane) -> Optional[int]:
    rc, out = lane.run(["pgrep", "-x", APP_NAME], 5)
    if rc != 0 or not out.split():
        return None
    return int(out.split()[0])


def normalise_app(lane: Lane, notes: List[str]) -> bool:
    """Quit ContainerBar through AppleScript (no signal) and relaunch it."""
    old = pgrep_app(lane)
    if old is not None:
        lane.run(["osascript", "-e", 'quit app "%s"' % APP_NAME], 15)
        for _ in range(40):
            if pgrep_app(lane) is None:
                break
            lane.clock.sleep(0.5)
        if pgrep_app(lane) is not None:
            notes.append("ContainerBar refused to quit (a modal sheet may block it)")
            return False
    lane.run(["open", "-a", lane.app_path], 15)
    for _ in range(60):
        new = pgrep_app(lane)
        if new is not None and new != old:
            notes.append("windows-normalised: ContainerBar relaunched (pid %s -> %d)" % (old, new))
            return True
        lane.clock.sleep(0.5)
    notes.append("ContainerBar did not relaunch")
    return False


def _write_marker(lane: Lane, session: Dict[str, object]) -> None:
    write_json(lane.marker, {"t0": session["t0"], "session": session["session"],
                             "written": lane.clock.now()})


def _clear_recovery(lane: Lane, notes: List[str]) -> None:
    """After a successful quit and relaunch: drop the old marker and the GUI flag."""
    for path, label in ((lane.marker, "old run marker deleted"),
                        (lane.gui_flag, "gui-cleanup-pending cleared")):
        try:
            path.unlink()
            notes.append(label)
        except FileNotFoundError:
            pass


def _restore_failed(lane: Lane, notes: List[str]) -> Dict[str, object]:
    release_lock(lane)
    notify(lane, "ContainerBar QA BLOCKED restore-failed: recovery of the previous run's "
                 "marker failed; marker kept for the hourly backstop. %s" % "; ".join(notes[-3:]))
    return {"status": BLOCKED, "reason": "restore-failed", "notes": notes}


def preflight(lane: Lane, session_id: str,
              spawn: Callable[[Lane, str, float], Holder] = spawn_holder) -> Dict[str, object]:
    session = new_session(lane, session_id)
    run_id = str(session["session"])
    notes: List[str] = ["deadline: waits end at T0+480s, case cut-off T0+1380s"]
    deadline = float(session["wait_deadline"])

    while True:
        busy, why = ci_busy(lane, deadline)
        notes.extend(n for n in why if n == "runner-api-unavailable" and n not in notes)
        if not busy:
            break
        if lane.clock.now() + CI_RECHECK_S > deadline:
            notes.append("CI wait ended busy at %s (%s)" % (_stamp(lane, session), ", ".join(why)))
            return {"status": BLOCKED, "reason": "ci-busy", "notes": notes}
        lane.clock.sleep(CI_RECHECK_S)
    notes.append("CI wait ended idle at %s" % _stamp(lane, session))

    if lane.clock.now() >= deadline or not acquire_lock(lane, session, notes, spawn):
        notes.append("lock wait ended busy at %s" % _stamp(lane, session))
        return {"status": BLOCKED, "reason": "desktop-busy", "notes": notes}
    notes.append("lock wait ended acquired at %s" % _stamp(lane, session))
    publish_session(lane, session)

    # CI may have started while we waited for the lock: look again before any
    # recovery touches the app.
    busy, why = ci_busy(lane, lane.clock.now() + RECHECK_BUDGET_S)
    if busy:
        release_lock(lane, run_id)
        notes.append("CI busy after the lock was acquired (%s); lock released" % ", ".join(why))
        return {"status": BLOCKED, "reason": "ci-busy", "notes": notes}

    marker_left = lane.marker.exists()
    gui_pending = lane.gui_flag.exists()
    if marker_left:
        notes.append("previous run left a marker; recovering")
        ok, restore_notes = restore(lane, keep_marker=True)
        notes.extend(restore_notes)
        if not ok:
            return _restore_failed(lane, notes)
    elif gui_pending:
        notes.append("gui-cleanup-pending: the hourly backstop restored an aborted run without a GUI")
    if marker_left or gui_pending:
        if not normalise_app(lane, notes):
            return {"status": NEEDS_NORMALISE, "reason": "close-dialogs-then-normalise",
                    "notes": notes}
        _clear_recovery(lane, notes)
    _write_marker(lane, session)
    notes.append("run marker written")
    return {"status": READY, "reason": "", "notes": notes}


def normalise_after_dialogs(lane: Lane) -> Dict[str, object]:
    """Second attempt after the agent closed Settings/Sparkle by accessibility id."""
    notes: List[str] = []
    session = load_session(lane)
    if session is None:
        return {"status": BLOCKED, "reason": "no-session", "notes": notes}
    if not normalise_app(lane, notes):
        return _restore_failed(lane, notes)
    _clear_recovery(lane, notes)
    _write_marker(lane, session)
    notes.append("run marker written")
    return {"status": READY, "reason": "", "notes": notes}


def print_result(result: Dict[str, object]) -> int:
    for line in result.get("notes", []):
        print("note: %s" % line)
    status = result["status"]
    if status == READY:
        print("READY")
        return 0
    if status == NEEDS_NORMALISE:
        print("NEEDS-NORMALISE %s" % result["reason"])
        return 3
    print("BLOCKED %s" % result["reason"])
    sys.stdout.flush()
    return 2
