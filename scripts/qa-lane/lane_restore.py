"""Restore and the Unix-socket forward for the ContainerBar QA lane (CB-105).

`restore()` is the body of containerbar-qa-restore.sh: everything that needs
no GUI (api-start, fixture reset when not at baseline, the recorded SSH
forward stopped by its PID and its socket removed, the run marker deleted).
Preferences are never touched here; the next pass's step 0 restores them.

The only process this code ever signals is the SSH forward the lane started,
by the PID it recorded, after checking that PID's command line still is that
forward. Nothing is stopped by name or pattern.
"""
from __future__ import annotations

import os
import signal
import stat
import subprocess
from pathlib import Path
from typing import Callable, List, Optional, Tuple

from lane_core import REMOTE_SOCKET, Lane, baseline_diff, fixture_status, read_json, write_json

SOCKET_WAIT_S = 10
FORWARD_EXIT_WAIT_S = 5


def default_terminate(pid: int) -> None:
    os.kill(pid, signal.SIGTERM)


def pid_command(lane: Lane, pid: int) -> Optional[str]:
    rc, out = lane.run(["ps", "-o", "command=", "-p", str(pid)], 5)
    if rc != 0 or not out.strip():
        return None
    return out.strip()


def is_our_forward(command: Optional[str], socket_path: str) -> bool:
    """The recorded PID still runs our ssh forward (guards against PID reuse)."""
    if not command:
        return False
    parts = command.split()
    return bool(parts) and os.path.basename(parts[0]) == "ssh" and socket_path in command \
        and REMOTE_SOCKET in command


def stop_forward(lane: Lane, notes: List[str],
                 terminate: Callable[[int], None] = default_terminate) -> bool:
    """Stop the recorded forward by PID and remove its socket. True when clean."""
    record = read_json(lane.forward_file) or {}
    socket_path = str(record.get("socket") or lane.socket)
    pid = record.get("pid")
    clean = True
    if isinstance(pid, int):
        command = pid_command(lane, pid)
        if command is None:
            notes.append("forward pid %d already gone" % pid)
        elif is_our_forward(command, socket_path):
            try:
                terminate(pid)
            except ProcessLookupError:
                pass
            for _ in range(FORWARD_EXIT_WAIT_S * 2):
                if pid_command(lane, pid) is None:
                    break
                lane.clock.sleep(0.5)
            if pid_command(lane, pid) is None:
                notes.append("forward pid %d stopped" % pid)
            else:
                notes.append("forward pid %d did not exit" % pid)
                clean = False
        else:
            notes.append("forward pid %d is not our ssh forward; left alone" % pid)
    for path in {socket_path, str(lane.socket)}:
        try:
            os.unlink(path)
            notes.append("removed socket %s" % path)
        except FileNotFoundError:
            pass
        except OSError as err:
            notes.append("could not remove socket %s: %s" % (path, err))
            clean = False
    if clean:
        try:
            lane.forward_file.unlink()
        except FileNotFoundError:
            pass
    return clean


def restore(lane: Lane, keep_marker: bool = False,
            terminate: Callable[[int], None] = default_terminate) -> Tuple[bool, List[str]]:
    """No-GUI restore. Returns (ok, run-notes lines)."""
    notes: List[str] = []
    ok = True
    rc, _ = lane.run(["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes",
                      "cbqa-ctl", "api-start"], 30)
    notes.append("cbqa-ctl api-start rc=%d" % rc)
    if rc != 0:
        ok = False

    state, states = fixture_status(lane)
    diffs = baseline_diff(states) if states is not None else ["status %s" % state]
    if diffs:
        notes.append("fixtures not at baseline: %s" % "; ".join(diffs))
        rc, _ = lane.run(["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes",
                          "cbqa-ctl", "reset"], 90)
        notes.append("cbqa-ctl reset rc=%d" % rc)
        state, states = fixture_status(lane)
        diffs = baseline_diff(states) if states is not None else ["status %s" % state]
        if diffs:
            notes.append("fixtures still not at baseline: %s" % "; ".join(diffs))
            ok = False
        else:
            notes.append("fixtures at baseline after reset")
    else:
        notes.append("fixtures at baseline")

    if not stop_forward(lane, notes, terminate):
        ok = False

    if not ok:
        notes.append("run marker kept: restore failed")
    elif keep_marker:
        notes.append("run marker kept (--keep-marker)")
    else:
        try:
            lane.marker.unlink()
            notes.append("run marker deleted")
        except FileNotFoundError:
            pass
    return ok, notes


def is_socket(path: Path) -> bool:
    try:
        return stat.S_ISSOCK(os.stat(str(path)).st_mode)
    except OSError:
        return False


def forward_argv(lane: Lane) -> List[str]:
    return ["ssh", "-nNT", "-o", "ExitOnForwardFailure=yes", "-o", "StreamLocalBindUnlink=yes",
            "-L", "%s:%s" % (lane.socket, REMOTE_SOCKET), "cbqa-tunnel"]


def start_forward(lane: Lane, spawn: Optional[Callable[[List[str]], int]] = None,
                  terminate: Callable[[int], None] = default_terminate) -> Tuple[bool, List[str]]:
    """Unix-socket leg preparation: clear leftovers, start the forward, wait for its socket."""
    notes: List[str] = []
    stop_forward(lane, notes, terminate)
    lane.socket.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    argv = forward_argv(lane)
    pid = (spawn or _spawn_detached)(argv)
    write_json(lane.forward_file, {"pid": pid, "socket": str(lane.socket)})
    notes.append("forward started pid %d" % pid)
    waited = 0.0
    while waited < SOCKET_WAIT_S:
        if is_socket(lane.socket):
            notes.append("socket ready after %.1fs" % waited)
            return True, notes
        lane.clock.sleep(0.5)
        waited += 0.5
    notes.append("socket did not appear within %ds: forward-failed" % SOCKET_WAIT_S)
    stop_forward(lane, notes, terminate)
    return False, notes


def _spawn_detached(argv: List[str]) -> int:
    proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True)
    return proc.pid
