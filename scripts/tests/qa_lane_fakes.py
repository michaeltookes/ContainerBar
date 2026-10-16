"""Test doubles for the QA lane tests: a scripted command runner and a fake clock."""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

LANE_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "qa-lane")
if LANE_DIR not in sys.path:
    sys.path.insert(0, LANE_DIR)

from lane_core import FIXTURES, Lane  # noqa: E402


class FakeClock:
    def __init__(self, start: float = 1_800_000_000.0):
        self.t = start
        self.start = start

    def now(self) -> float:
        return self.t

    def sleep(self, seconds: float) -> None:
        self.t += seconds

    def elapsed(self) -> float:
        return self.t - self.start


def status_json(overrides=None, extra=None) -> str:
    states = dict(FIXTURES)
    states.update(overrides or {})
    containers = [{"name": n, "state": s} for n, s in states.items() if s is not None]
    for name in extra or []:
        containers.append({"name": name, "state": "running"})
    return json.dumps({"containers": containers})


class FakeRunner:
    """Answers commands from handlers keyed by a joined-argv prefix; records calls."""

    def __init__(self):
        self.calls = []
        self.handlers = []
        self.app_pid = None          # pgrep -x ContainerBar
        self.worker = False          # pgrep -x Runner.Worker
        self.runners = {}            # repo -> list of runners, or None for API failure
        self.status = [status_json()]  # successive cbqa-ctl status answers (last repeats)
        self.processes = {}          # pid -> command line, for ps -o command=
        self.quit_works = True
        self.next_app_pid = 5000

    def on(self, prefix, handler):
        self.handlers.append((prefix, handler))

    def __call__(self, argv, timeout):
        argv = list(argv)
        self.calls.append(argv)
        joined = " ".join(argv)
        for prefix, handler in self.handlers:
            if joined.startswith(prefix):
                return handler(argv)
        if argv[:3] == ["pgrep", "-x", "Runner.Worker"]:
            return (0, "4242\n") if self.worker else (1, "")
        if argv[:3] == ["pgrep", "-x", "ContainerBar"]:
            return (0, "%d\n" % self.app_pid) if self.app_pid else (1, "")
        if argv[:2] == ["gh", "api"]:
            repo = argv[2].split("/actions")[0][len("repos/"):]
            runners = self.runners.get(repo, [])
            if runners is None:
                return 1, ""
            return 0, json.dumps({"runners": runners})
        if argv[0] == "ssh" and argv[-1] == "status":
            answer = self.status[0] if len(self.status) == 1 else self.status.pop(0)
            return (2, "") if answer is None else (0, answer + "\n")
        if argv[0] == "ssh":
            return 0, "{}\n"
        if argv[:3] == ["ps", "-o", "command="]:
            cmd = self.processes.get(int(argv[-1]))
            return (0, cmd + "\n") if cmd else (1, "")
        if argv[0] == "osascript":
            if self.quit_works:
                self.app_pid = None
            return 0, ""
        if argv[:2] == ["open", "-a"]:
            self.app_pid = self.next_app_pid
            self.next_app_pid += 1
            return 0, ""
        if argv[0] == "spctl":
            return 0, ""
        return 0, ""

    def ran(self, *words) -> bool:
        return any(all(w in call for w in words) for call in self.calls)


def make_lane(test, runner=None, clock=None, extra_env=None):
    tmp = tempfile.TemporaryDirectory()
    test.addCleanup(tmp.cleanup)
    root = Path(tmp.name)
    env = {
        "HOME": str(root / "home"),
        "CBQA_WORKSPACE": str(root / "ws"),
        "CBQA_RUNNER_NAMES": "mini-runner-1,mini-runner-2",
        "CBQA_APP_PATH": str(root / "ContainerBar.app"),
        "CBQA_OPENCLAW_ENV": str(root / "openclaw.env"),
    }
    env.update(extra_env or {})
    lane = Lane(env=env, run=runner or FakeRunner(), clock=clock or FakeClock())
    lane.state_dir.mkdir(parents=True, exist_ok=True)
    return lane, root
