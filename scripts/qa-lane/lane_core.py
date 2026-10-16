"""Shared pieces of the ContainerBar QA lane tooling (CB-105).

Paths, private configuration, the command runner, the run deadline, the
CI-busy predicate and the cbqa fixture baseline. Everything here is safe to
publish: hosts, runner names, channels and webhooks come from private files
in the workspace at run time, never from this repo.

Python 3.9 compatible (the agent Mini runs /usr/bin/python3 3.9).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional, Sequence, Tuple

# One deadline per run (architecture section 7, CB-110).
WAIT_BUDGET_S = 480       # CI wait + lock wait share this, both end at T0 + 480
CASE_CUTOFF_S = 1380      # no case starts after T0 + 1380
OUTER_TIMEOUT_S = 1800    # the cron job's timeout; 420 s reserved for restore
STALE_MARKER_S = 31 * 60  # backstop threshold for a left-over run marker
CI_RECHECK_S = 60         # CI wait rechecks once a minute
LOCK_RECHECK_S = 15

FIXTURES = {
    "cbqa-web": "running",
    "cbqa-logs": "running",
    "cbqa-target": "running",
    "cbqa-limited": "running",
    "cbqa-stopped": "exited",
    "cbqa-tty": "running",
}

APP_NAME = "ContainerBar"
APP_PATH = "/Applications/ContainerBar.app"
REMOTE_SOCKET = "/run/cbqa-api/podman.sock"
DEFAULT_RUNNER_REPOS = "michaeltookes/ContainerBar,michaeltookes/sentwise"

Result = Tuple[int, str]
OUT_OF_TIME = 124
RunFn = Callable[[Sequence[str], float], Result]


def real_run(argv: Sequence[str], timeout: float) -> Result:
    """Run argv (never through a shell); return (exit code, stdout)."""
    try:
        done = subprocess.run(list(argv), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              stdin=subprocess.DEVNULL, timeout=timeout, text=True)
    except FileNotFoundError:
        return 127, ""
    except subprocess.TimeoutExpired:
        return 124, ""
    return done.returncode, done.stdout


class Clock:
    """Wall clock; tests substitute a fake whose sleep advances time."""

    def now(self) -> float:
        return time.time()

    def sleep(self, seconds: float) -> None:
        time.sleep(seconds)


def read_env_file(path: Path) -> Dict[str, str]:
    """Parse KEY=VALUE lines without executing the file (never sourced)."""
    values: Dict[str, str] = {}
    try:
        text = path.read_text()
    except OSError:
        return values
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        if key.startswith("export "):
            key = key[len("export "):].strip()
        values[key] = value.strip().strip('"').strip("'")
    return values


class Lane:
    """Paths and private settings for one host, resolved from the environment."""

    def __init__(self, env: Optional[Dict[str, str]] = None,
                 run: RunFn = real_run, clock: Optional[Clock] = None):
        env = dict(os.environ if env is None else env)
        home = Path(env.get("HOME", str(Path.home())))
        self.home = home
        self.workspace = Path(env.get("CBQA_WORKSPACE", str(home / ".openclaw" / "workspace")))
        self.state_dir = self.workspace / "qa" / "containerbar"
        self.artifacts = self.workspace / "artifacts" / "containerbar-qa"
        self.marker = self.state_dir / "run-active"
        self.session_file = self.state_dir / "session.json"
        self.forward_file = self.state_dir / "forward.json"
        self.release_prefix = "lock-release."
        self.gui_flag = self.state_dir / "gui-cleanup-pending"
        self.lock_dir = Path(env.get("CBQA_LOCK_DIR",
                                     str(self.workspace / "artifacts" / "sentwise-qa" / "device.lock")))
        self.lock_tool = Path(env.get("CBQA_LOCK_TOOL",
                                      str(self.workspace / "tools" / "sentwise-qa" / "device_lock.py")))
        self.python = env.get("CBQA_PYTHON", "/usr/bin/python3")
        self.socket = Path(env.get("CBQA_SOCKET", str(home / "qa" / "containerbar" / "podman.sock")))
        self.app_path = env.get("CBQA_APP_PATH", APP_PATH)
        private = read_env_file(self.state_dir / "lane.env")
        private.update({k: v for k, v in env.items() if k.startswith("CBQA_")})
        self.settings = private
        self.openclaw_env = Path(env.get("CBQA_OPENCLAW_ENV", str(home / ".openclaw" / ".env")))
        self.run = run
        self.clock = clock or Clock()

    def call(self, argv: Sequence[str], timeout: float,
             deadline: Optional[float] = None) -> Result:
        """Run argv with its timeout capped by an absolute deadline.

        Past the deadline nothing runs and the result is (124, "") like a timeout.
        """
        if deadline is not None:
            timeout = min(timeout, deadline - self.clock.now())
            if timeout <= 0:
                return OUT_OF_TIME, ""
        return self.run(argv, timeout)

    def release_file_for(self, run_id: str) -> Path:
        """One release file per run: a holder watches only its own (PR 76 P1)."""
        safe = re.sub(r"[^A-Za-z0-9._-]", "_", run_id) or "_"
        return self.state_dir / (self.release_prefix + safe)

    def setting(self, key: str, default: str = "") -> str:
        return self.settings.get(key, default)

    def runner_names(self) -> List[str]:
        return [n.strip() for n in self.setting("CBQA_RUNNER_NAMES").split(",") if n.strip()]

    def runner_repos(self) -> List[str]:
        raw = self.setting("CBQA_RUNNER_REPOS", DEFAULT_RUNNER_REPOS)
        return [r.strip() for r in raw.split(",") if r.strip()]


# ---------------------------------------------------------------- CI-busy


def ci_busy(lane: Lane, deadline: Optional[float] = None) -> Tuple[bool, List[str]]:
    """The CI-busy predicate (architecture section 7).

    Busy if `pgrep -x Runner.Worker` prints a PID, or the runners API lists one
    of this host's runners with busy: true. An unreachable API (or no runner
    names configured) is noted as runner-api-unavailable and never counts as
    idle evidence on its own; the Runner.Worker check then decides alone.

    Every probe's timeout is capped by `deadline`. When no time is left for
    the Runner.Worker check, CI cannot be observed and counts as busy
    (ci-check-out-of-time); API calls that run out of time count as an
    unavailable API.
    """
    notes: List[str] = []
    rc, out = lane.call(["pgrep", "-x", "Runner.Worker"], 5, deadline)
    if rc == 0 and out.strip():
        notes.append("runner-worker-present")
        return True, notes
    if rc == OUT_OF_TIME:
        notes.append("ci-check-out-of-time")
        return True, notes
    names = set(lane.runner_names())
    if not names:
        notes.append("runner-api-unavailable")
        return False, notes
    api_failed = False
    for repo in lane.runner_repos():
        rc, out = lane.call(["gh", "api", "repos/%s/actions/runners?per_page=100" % repo], 10,
                            deadline)
        if rc != 0:
            api_failed = True
            continue
        try:
            runners = json.loads(out).get("runners", [])
        except (ValueError, AttributeError):
            api_failed = True
            continue
        for runner in runners:
            if runner.get("name") in names and runner.get("busy") is True:
                notes.append("runner-busy:%s" % runner.get("name"))
                return True, notes
    if api_failed:
        notes.append("runner-api-unavailable")
    return False, notes


# ---------------------------------------------------------------- deadline


def new_session(lane: Lane, session: str) -> Dict[str, object]:
    """Compute the run's deadlines once, at session start (CB-110).

    In memory only: a pass still waiting for the lock must not overwrite the
    session file of the pass that holds it. publish_session() writes it once
    the lock is held.
    """
    t0 = lane.clock.now()
    data = {
        "session": session,
        "t0": t0,
        "wait_deadline": t0 + WAIT_BUDGET_S,
        "case_cutoff": t0 + CASE_CUTOFF_S,
        "outer_deadline": t0 + OUTER_TIMEOUT_S,
    }
    return data


def publish_session(lane: Lane, session: Dict[str, object]) -> None:
    """Called only by the lock holder's pass."""
    write_json(lane.session_file, session)


def load_session(lane: Lane) -> Optional[Dict[str, object]]:
    return read_json(lane.session_file)


def case_gate(lane: Lane) -> Tuple[bool, str]:
    """Before every case: no wait, only the cut-off and the CI predicate.

    The clock is read again after the CI probes, so slow probes never grant a
    case inside the restore reserve.
    """
    session = load_session(lane)
    if session is None:
        return False, "no-session"
    cutoff = float(session["case_cutoff"])
    if lane.clock.now() > cutoff:
        return False, "time-budget"
    busy, notes = ci_busy(lane, cutoff)
    if lane.clock.now() >= cutoff or "ci-check-out-of-time" in notes:
        return False, "time-budget"
    if busy:
        return False, "ci-busy"
    return True, "ok"


# ---------------------------------------------------------------- fixtures


def fixture_status(lane: Lane, deadline: Optional[float] = None
                   ) -> Tuple[str, Optional[Dict[str, str]]]:
    """('ok', states) | ('down', None) | ('unparsable', None)."""
    rc, out = lane.call(["ssh", "-o", "ConnectTimeout=5", "-o", "BatchMode=yes",
                         "cbqa-ctl", "status"], 20, deadline)
    if rc != 0:
        return "down", None
    try:
        containers = json.loads(out.strip().splitlines()[-1])["containers"]
        return "ok", {c["name"]: c["state"] for c in containers}
    except (ValueError, KeyError, IndexError, TypeError):
        return "unparsable", None


def baseline_diff(states: Dict[str, str]) -> List[str]:
    """Differences from the six-fixture baseline; empty means baseline."""
    diffs = []
    for name, want in FIXTURES.items():
        got = states.get(name)
        if got is None:
            diffs.append("%s missing" % name)
        elif got != want:
            diffs.append("%s %s (want %s)" % (name, got, want))
    for name in sorted(set(states) - set(FIXTURES)):
        diffs.append("%s unexpected" % name)
    return diffs


# ---------------------------------------------------------------- files


def read_json(path: Path) -> Optional[Dict[str, object]]:
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def write_json(path: Path, data: Dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=1, sort_keys=True))
    os.replace(str(tmp), str(path))


def marker_age(lane: Lane) -> Optional[float]:
    """Seconds since the marker's recorded session start; None if no marker."""
    if not lane.marker.exists():
        return None
    data = read_json(lane.marker) or {}
    started = data.get("t0")
    if not isinstance(started, (int, float)):
        try:
            started = lane.marker.stat().st_mtime
        except OSError:
            return None
    return max(0.0, lane.clock.now() - float(started))
