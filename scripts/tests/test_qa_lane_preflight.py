#!/usr/bin/env python3
"""CB-105 story 6 AC2-AC4 and CB-110/CB-112: CI wait, desktop lock, deadline, marker recovery.

Run: python3 -m unittest discover -s scripts/tests -p 'test_qa_lane*.py'
"""
from __future__ import annotations

import json
import os
import sys
import time
import unittest

from qa_lane_fakes import FakeClock, FakeRunner, make_lane, status_json

import lane_core
import lane_preflight
from lane_core import case_gate, ci_busy
from lane_preflight import BLOCKED, NEEDS_NORMALISE, READY, normalise_after_dialogs, preflight


class FakeLock:
    """Simulates the shared device lock: another brief holds it until `other_until`."""

    def __init__(self, lane, clock, other_until=None):
        self.lane, self.clock, self.other_until = lane, clock, other_until
        self.spawns = 0

    def spawn(self, lane, run_id, timeout_s):
        self.spawns += 1
        lock = self

        class Holder:
            pid = 7000 + lock.spawns

            def __init__(self):
                self.code = None
                if lock.other_until is not None and lock.clock.now() < lock.other_until:
                    self.code = 75
                else:
                    lane.lock_dir.mkdir(parents=True, exist_ok=True)
                    (lane.lock_dir / "owner.json").write_text(json.dumps({"run": run_id}))

            def poll(self):
                return self.code

        return Holder()


def run_preflight(test, runner=None, clock=None, other_until=None, marker=None):
    clock = clock or FakeClock()
    runner = runner or FakeRunner()
    lane, _ = make_lane(test, runner, clock)
    if marker is not None:
        lane_core.write_json(lane.marker, marker)
    lock = FakeLock(lane, clock, other_until)
    result = preflight(lane, "cbqa-daily-test", spawn=lock.spawn)
    return result, lane, runner, clock, lock


class CIBusyPredicateTests(unittest.TestCase):
    def test_runner_worker_process_means_busy(self):
        runner = FakeRunner()
        runner.worker = True
        lane, _ = make_lane(self, runner)
        busy, notes = ci_busy(lane)
        self.assertTrue(busy)
        self.assertIn("runner-worker-present", notes)

    def test_api_busy_runner_on_this_host_means_busy(self):
        runner = FakeRunner()
        runner.runners["michaeltookes/sentwise"] = [{"name": "mini-runner-2", "busy": True}]
        lane, _ = make_lane(self, runner)
        self.assertTrue(ci_busy(lane)[0])

    def test_busy_runner_on_another_host_is_ignored(self):
        runner = FakeRunner()
        runner.runners["michaeltookes/ContainerBar"] = [{"name": "beelink-runner", "busy": True},
                                                        {"name": "mini-runner-1", "busy": False}]
        lane, _ = make_lane(self, runner)
        self.assertEqual(ci_busy(lane), (False, []))

    def test_api_failure_records_unavailable_and_worker_check_decides(self):
        runner = FakeRunner()
        runner.runners["michaeltookes/ContainerBar"] = None
        lane, _ = make_lane(self, runner)
        busy, notes = ci_busy(lane)
        self.assertFalse(busy)
        self.assertIn("runner-api-unavailable", notes)
        runner.worker = True
        self.assertTrue(ci_busy(lane)[0])

    def test_no_runner_names_configured_is_unavailable_not_idle_evidence(self):
        runner = FakeRunner()
        lane, _ = make_lane(self, runner, extra_env={"CBQA_RUNNER_NAMES": ""})
        busy, notes = ci_busy(lane)
        self.assertFalse(busy)
        self.assertEqual(notes, ["runner-api-unavailable"])
        self.assertFalse(runner.ran("gh"))


class DeadlineTests(unittest.TestCase):
    def test_ci_busy_whole_preflight_blocks_by_t0_plus_480_without_lock_wait(self):
        runner = FakeRunner()
        runner.worker = True
        result, lane, _, clock, lock = run_preflight(self, runner)
        self.assertEqual((result["status"], result["reason"]), (BLOCKED, "ci-busy"))
        self.assertLessEqual(clock.elapsed(), 480)
        self.assertEqual(lock.spawns, 0)
        self.assertFalse(lane.marker.exists())

    def test_ci_rechecks_once_a_minute(self):
        runner = FakeRunner()
        runner.worker = True
        clock = FakeClock()
        seen = []
        original = runner.__call__

        def record(argv, timeout):
            if argv[:2] == ["pgrep", "-x"]:
                seen.append(clock.elapsed())
            return original(argv, timeout)

        lane, _ = make_lane(self, record, clock)
        preflight(lane, "s0", spawn=FakeLock(lane, clock).spawn)
        # T0 ... T0+420; at T0+480 no time is left to probe, so the wait ends busy.
        self.assertEqual(seen, [60.0 * i for i in range(8)])

    def test_lock_wait_gets_only_what_is_left_of_the_shared_budget(self):
        clock = FakeClock()
        runner = FakeRunner()
        runner.worker = True
        original = runner.__call__

        def ci_until_300(argv, timeout):
            runner.worker = clock.elapsed() < 300
            return original(argv, timeout)

        runner_fn = ci_until_300
        lane, _ = make_lane(self, runner_fn, clock)
        lock = FakeLock(lane, clock, other_until=clock.start + 10_000)
        result = preflight(lane, "s1", spawn=lock.spawn)
        self.assertEqual((result["status"], result["reason"]), (BLOCKED, "desktop-busy"))
        self.assertLessEqual(clock.elapsed(), 480)
        self.assertGreaterEqual(clock.elapsed(), 300)
        notes = " ".join(result["notes"])
        self.assertIn("CI wait ended idle at T0+300s", notes)
        self.assertIn("lock wait ended busy", notes)

    def test_both_clear_gives_ready_with_cutoff_at_t0_plus_1380(self):
        result, lane, _, clock, _ = run_preflight(self, other_until=FakeClock().start + 120)
        self.assertEqual(result["status"], READY)
        session = lane_core.load_session(lane)
        self.assertEqual(session["case_cutoff"] - session["t0"], 1380)
        self.assertEqual(session["outer_deadline"] - session["case_cutoff"], 420)
        self.assertTrue(lane.marker.exists())

    def test_case_gate_blocks_after_cutoff_and_on_ci_without_waiting(self):
        result, lane, runner, clock, _ = run_preflight(self)
        self.assertEqual(result["status"], READY)
        self.assertEqual(case_gate(lane), (True, "ok"))
        runner.worker = True
        before = clock.now()
        self.assertEqual(case_gate(lane), (False, "ci-busy"))
        self.assertEqual(clock.now(), before)
        runner.worker = False
        clock.t = lane_core.load_session(lane)["t0"] + 1381
        self.assertEqual(case_gate(lane), (False, "time-budget"))


class CodexRoundOneTests(unittest.TestCase):
    """PR 76 Codex round 1, items 5-8."""

    def test_waiting_pass_never_overwrites_the_active_session(self):
        clock = FakeClock()
        lane, _ = make_lane(self, FakeRunner(), clock)
        active = {"session": "active-pass", "t0": 1.0, "case_cutoff": 1381.0}
        lane_core.write_json(lane.session_file, active)
        lock = FakeLock(lane, clock, other_until=clock.start + 10_000)
        result = preflight(lane, "newcomer", spawn=lock.spawn)
        self.assertEqual(result["reason"], "desktop-busy")
        self.assertEqual(lane_core.load_session(lane), active)

    def test_ci_busy_blocked_pass_leaves_session_file_alone(self):
        runner = FakeRunner()
        runner.worker = True
        clock = FakeClock()
        lane, _ = make_lane(self, runner, clock)
        lane_core.write_json(lane.session_file, {"session": "active-pass"})
        preflight(lane, "newcomer", spawn=FakeLock(lane, clock).spawn)
        self.assertEqual(lane_core.load_session(lane)["session"], "active-pass")

    def test_ci_recheck_after_lock_blocks_before_any_recovery(self):
        runner = FakeRunner()
        runner.app_pid = 4100
        clock = FakeClock()
        lane, _ = make_lane(self, runner, clock)
        lane_core.write_json(lane.marker, {"t0": 1.0, "session": "old"})
        lock = FakeLock(lane, clock)
        original_spawn = lock.spawn

        def spawn_then_ci_starts(ln, run_id, timeout_s):
            holder = original_spawn(ln, run_id, timeout_s)
            runner.worker = True   # a job lands while we were taking the lock
            return holder

        released = []
        original = lane_preflight.release_lock
        lane_preflight.release_lock = lambda ln, run_id=None: released.append(run_id) or True
        self.addCleanup(setattr, lane_preflight, "release_lock", original)
        result = preflight(lane, "s6", spawn=spawn_then_ci_starts)
        self.assertEqual((result["status"], result["reason"]), (BLOCKED, "ci-busy"))
        self.assertEqual(released, ["s6"])
        self.assertFalse(runner.ran("osascript"))
        self.assertFalse(runner.ran("api-start"))
        self.assertEqual(runner.app_pid, 4100)
        self.assertEqual(lane_core.read_json(lane.marker)["session"], "old")

    def test_slow_ci_probes_cannot_grant_a_case_inside_the_restore_reserve(self):
        result, lane, runner, clock, _ = run_preflight(self)
        self.assertEqual(result["status"], READY)
        clock.t = lane_core.load_session(lane)["t0"] + 1379
        runner.costs = [("gh api", 10)]          # two API calls: 20 s
        self.assertEqual(case_gate(lane), (False, "time-budget"))
        self.assertLessEqual(clock.now(), lane_core.load_session(lane)["case_cutoff"] + 0.001)

    def test_slow_ci_probes_never_run_past_the_wait_deadline(self):
        clock = FakeClock()
        runner = FakeRunner()
        repos = ["michaeltookes/repo%d" % i for i in range(6)]
        runner.runners[repos[-1]] = [{"name": "mini-runner-1", "busy": True}]
        runner.costs = [("gh api", 9)]           # six slow API calls per probe: 54 s
        lane, _ = make_lane(self, runner, clock, extra_env={"CBQA_RUNNER_REPOS": ",".join(repos)})
        lock = FakeLock(lane, clock)
        result = preflight(lane, "slow", spawn=lock.spawn)
        self.assertEqual(result["status"], BLOCKED)
        self.assertLessEqual(clock.elapsed(), 480)
        self.assertEqual(lock.spawns, 0)
        self.assertTrue(all(t <= 10 for t in runner.timeouts))

    def test_no_lock_attempt_after_the_wait_deadline(self):
        clock = FakeClock()
        runner = FakeRunner()
        original = runner.__call__

        def idle_from_420(argv, timeout):
            runner.worker = clock.elapsed() < 420
            return original(argv, timeout)

        repos = ",".join("michaeltookes/repo%d" % i for i in range(6))
        lane, _ = make_lane(self, idle_from_420, clock, extra_env={"CBQA_RUNNER_REPOS": repos})
        runner.clock = clock
        runner.costs = [("pgrep -x Runner.Worker", 3), ("gh api", 10)]
        lock = FakeLock(lane, clock)
        result = preflight(lane, "late", spawn=lock.spawn)
        self.assertEqual(result["reason"], "desktop-busy")
        self.assertLessEqual(clock.elapsed(), 480)
        self.assertEqual(lock.spawns, 0)

    def test_giving_up_tells_a_pending_holder_to_let_go(self):
        clock = FakeClock()
        lane, _ = make_lane(self, FakeRunner(), clock)

        class Waiting:
            pid = 9999

            def poll(self):
                return None   # still queued on the lock when the deadline comes

        result = preflight(lane, "queued", spawn=lambda ln, run_id, t: Waiting())
        self.assertEqual(result["reason"], "desktop-busy")
        self.assertLessEqual(clock.elapsed(), 480)
        self.assertEqual(lane.release_file_for("queued").read_text(), "queued")


class PerRunReleaseFileTests(unittest.TestCase):
    """PR 76 round 3 P1: a contender's cancellation survives the owner's release."""

    def test_owner_release_never_touches_a_contenders_cancellation(self):
        clock = FakeClock()
        lane, _ = make_lane(self, FakeRunner(), clock)

        class Queued:
            pid = 9999

            def poll(self):
                return None

        # B times out while its holder is still queued on the lock.
        preflight(lane, "run-B", spawn=lambda ln, run_id, t: Queued())
        self.assertEqual(lane.release_file_for("run-B").read_text(), "run-B")
        # A, the owner, releases.
        lane.lock_dir.mkdir(parents=True, exist_ok=True)
        (lane.lock_dir / "owner.json").write_text(json.dumps({"run": "run-A"}))
        lane_core.publish_session(lane, {"session": "run-A"})
        original = lane_preflight.lock_owner_run
        calls = []

        def owner(ln):
            calls.append(1)
            return "run-A" if len(calls) == 1 else None

        lane_preflight.lock_owner_run = owner
        self.addCleanup(setattr, lane_preflight, "lock_owner_run", original)
        self.assertTrue(lane_preflight.release_lock(lane))
        # B's holder, when it finally gets the lock, still finds its cancellation.
        self.assertEqual(lane.release_file_for("run-B").read_text(), "run-B")
        before = clock.now()
        self.assertEqual(lane_preflight.hold(lane, "run-B", str(lane.release_file_for("run-B")),
                                             before + 600), 0)
        self.assertEqual(clock.now(), before)   # let go at once, not at the outer deadline
        self.assertFalse(lane.release_file_for("run-B").exists())  # consumed by its holder

    def test_holders_watch_only_their_own_file(self):
        clock = FakeClock()
        lane, _ = make_lane(self, FakeRunner(), clock)
        lane.state_dir.mkdir(parents=True, exist_ok=True)
        lane.release_file_for("run-A").write_text("run-A")
        start = clock.now()
        lane_preflight.hold(lane, "run-B", None, start + 30)
        self.assertGreaterEqual(clock.now() - start, 30)    # A's file did not release B
        self.assertTrue(lane.release_file_for("run-A").exists())

    def test_run_ids_map_to_safe_distinct_files(self):
        lane, _ = make_lane(self)
        a, b = lane.release_file_for("x/../y"), lane.release_file_for("x-y")
        self.assertEqual(a.parent, lane.state_dir)
        self.assertNotEqual(a, b)

    def test_old_release_files_are_pruned_young_ones_kept(self):
        clock = FakeClock()
        lane, _ = make_lane(self, FakeRunner(), clock)
        old, young = lane.release_file_for("old"), lane.release_file_for("young")
        old.write_text("old")
        young.write_text("young")
        os.utime(str(old), (clock.now() - 3 * 3600,) * 2)
        os.utime(str(young), (clock.now() - 60,) * 2)
        lane_preflight.prune_release_files(lane)
        self.assertFalse(old.exists())
        self.assertTrue(young.exists())


class GuiCleanupPendingTests(unittest.TestCase):
    """PR 76 Codex round 2 item 1: the backstop's GUI flag is honoured by step 0."""

    def flagged(self, runner):
        clock = FakeClock()
        lane, _ = make_lane(self, runner, clock)
        lane_core.write_json(lane.gui_flag, {"since": 1.0})
        return lane, clock

    def test_flag_alone_quits_and_relaunches_then_clears(self):
        runner = FakeRunner()
        runner.app_pid = 4100
        lane, clock = self.flagged(runner)
        result = preflight(lane, "g1", spawn=FakeLock(lane, clock).spawn)
        self.assertEqual(result["status"], READY)
        self.assertTrue(runner.ran("osascript"))
        self.assertNotEqual(runner.app_pid, 4100)
        self.assertFalse(lane.gui_flag.exists())
        self.assertFalse(runner.ran("api-start"))   # the no-GUI part already ran

    def test_flag_kept_until_a_normalise_succeeds(self):
        runner = FakeRunner()
        runner.app_pid = 4100
        runner.quit_works = False
        lane, clock = self.flagged(runner)
        result = preflight(lane, "g2", spawn=FakeLock(lane, clock).spawn)
        self.assertEqual(result["status"], NEEDS_NORMALISE)
        self.assertTrue(lane.gui_flag.exists())
        runner.quit_works = True
        self.assertEqual(normalise_after_dialogs(lane)["status"], READY)
        self.assertFalse(lane.gui_flag.exists())

    def test_pass_aborted_between_restore_and_gui_step_is_normalised_next_time(self):
        from lane_restore import restore
        runner = FakeRunner()
        runner.app_pid = 4100
        clock = FakeClock()
        lane, _ = make_lane(self, runner, clock)
        lane_core.write_json(lane.marker, {"t0": clock.now(), "session": "aborted"})
        ok, _ = restore(lane)                    # step 5, then the session dies
        self.assertTrue(ok)
        self.assertFalse(lane.marker.exists())
        result = preflight(lane, "next", spawn=FakeLock(lane, clock).spawn)
        self.assertEqual(result["status"], READY)
        self.assertTrue(runner.ran("osascript"))
        self.assertFalse(lane.gui_flag.exists())

    def test_hourly_backstop_then_next_pass_normalises(self):
        from lane_hourly import hourly
        runner = FakeRunner()
        runner.app_pid = 4100
        clock = FakeClock(1800028800.0)   # 10:00 Central
        lane, _ = make_lane(self, runner, clock)
        lane_core.write_json(lane.marker, {"t0": clock.now() - 40 * 60})
        hourly(lane, fetch=lambda url, timeout: None, post=lambda url, text: True)
        self.assertFalse(lane.marker.exists())
        self.assertTrue(lane.gui_flag.exists())
        result = preflight(lane, "g3", spawn=FakeLock(lane, clock).spawn)
        self.assertEqual(result["status"], READY)
        self.assertTrue(any("windows-normalised" in n for n in result["notes"]))
        self.assertFalse(lane.gui_flag.exists())


class MarkerRecoveryTests(unittest.TestCase):
    def test_leftover_marker_is_recovered_and_app_normalised_before_new_marker(self):
        runner = FakeRunner()
        runner.app_pid = 4100
        runner.status = [status_json({"cbqa-target": "exited"}), status_json()]
        old = {"t0": 1.0, "session": "old-run"}
        result, lane, runner, _, _ = run_preflight(self, runner, marker=old)
        self.assertEqual(result["status"], READY)
        self.assertTrue(runner.ran("cbqa-ctl", "reset"))
        self.assertTrue(runner.ran("osascript"))
        self.assertNotEqual(runner.app_pid, 4100)
        self.assertEqual(lane_core.read_json(lane.marker)["session"], "cbqa-daily-test")
        self.assertTrue(any("windows-normalised" in n for n in result["notes"]))
        quit_index = next(i for i, c in enumerate(runner.calls) if c[0] == "osascript")
        reset_index = next(i for i, c in enumerate(runner.calls) if c[-1] == "reset")
        self.assertLess(reset_index, quit_index)

    def test_failed_recovery_keeps_old_marker_and_ends_restore_failed(self):
        runner = FakeRunner()
        runner.status = [None]
        old = {"t0": 1.0, "session": "old-run"}
        result, lane, *_ = run_preflight(self, runner, marker=old)
        self.assertEqual((result["status"], result["reason"]), (BLOCKED, "restore-failed"))
        self.assertEqual(lane_core.read_json(lane.marker)["session"], "old-run")
        self.assertFalse(runner.ran("osascript"))

    def test_restore_failed_posts_one_line_and_releases_lock(self):
        runner = FakeRunner()
        runner.status = [None]
        clock = FakeClock()
        lane, _ = make_lane(self, runner, clock, extra_env={"CBQA_ALERT_TARGET": "channel:123"})
        lane_core.write_json(lane.marker, {"t0": 1.0, "session": "old-run"})
        lock = FakeLock(lane, clock)
        released = []
        original = lane_preflight.release_lock
        lane_preflight.release_lock = lambda ln: released.append(True) or True
        self.addCleanup(setattr, lane_preflight, "release_lock", original)
        result = preflight(lane, "s2", spawn=lock.spawn)
        self.assertEqual(result["reason"], "restore-failed")
        sends = [c for c in runner.calls if c[:3] == ["openclaw", "message", "send"]]
        self.assertEqual(len(sends), 1)
        self.assertIn("channel:123", sends[0])
        self.assertEqual(released, [True])

    def test_quit_refused_asks_for_dialog_close_then_normalise_retry(self):
        runner = FakeRunner()
        runner.app_pid = 4100
        runner.quit_works = False
        result, lane, runner, _, _ = run_preflight(self, runner, marker={"t0": 1.0, "session": "old"})
        self.assertEqual(result["status"], NEEDS_NORMALISE)
        self.assertEqual(lane_core.read_json(lane.marker)["session"], "old")
        runner.quit_works = True
        retry = normalise_after_dialogs(lane)
        self.assertEqual(retry["status"], READY)
        self.assertEqual(lane_core.read_json(lane.marker)["session"], "cbqa-daily-test")

    def test_normalise_retry_failure_is_restore_failed_with_old_marker(self):
        runner = FakeRunner()
        runner.app_pid = 4100
        runner.quit_works = False
        result, lane, runner, _, _ = run_preflight(self, runner, marker={"t0": 1.0, "session": "old"})
        self.assertEqual(result["status"], NEEDS_NORMALISE)
        retry = normalise_after_dialogs(lane)
        self.assertEqual((retry["status"], retry["reason"]), (BLOCKED, "restore-failed"))
        self.assertEqual(lane_core.read_json(lane.marker)["session"], "old")

    def test_no_marker_writes_new_marker_without_restore(self):
        result, lane, runner, _, _ = run_preflight(self)
        self.assertEqual(result["status"], READY)
        self.assertFalse(runner.ran("api-start"))
        self.assertFalse(runner.ran("osascript"))


STUB_LOCK_TOOL = """
import json, os, shutil, subprocess, sys
args = sys.argv[1:]
lock = args[args.index("--lock") + 1]
run = args[args.index("--run") + 1]
cmd = args[args.index("--") + 1:]
try:
    os.mkdir(lock)
except FileExistsError:
    sys.exit(75)
open(os.path.join(lock, "owner.json"), "w").write(json.dumps({"run": run, "pid": os.getpid()}))
try:
    code = subprocess.call(cmd)
finally:
    shutil.rmtree(lock, ignore_errors=True)
sys.exit(code)
"""


class HoldTests(unittest.TestCase):
    def test_hold_stops_at_its_deadline_without_release(self):
        clock = FakeClock()
        lane, root = make_lane(self, FakeRunner(), clock)
        self.assertEqual(lane_preflight.hold(lane, "r", str(root / "never"), clock.now() + 30), 0)
        self.assertGreaterEqual(clock.elapsed(), 30)

    def test_hold_returns_when_release_names_this_run(self):
        lane, root = make_lane(self, FakeRunner())
        flag = root / "release"
        flag.write_text("other-run")
        clock = lane.clock
        self.assertEqual(lane_preflight.hold(lane, "r", str(flag), clock.now() + 5), 0)
        flag.write_text("r")
        start = clock.now()
        lane_preflight.hold(lane, "r", str(flag), clock.now() + 500)
        self.assertEqual(clock.now(), start)


class RealLockHolderTests(unittest.TestCase):
    """The detached holder keeps the shared lock across the pass and lets go on release."""

    def test_holder_acquires_holds_and_releases(self):
        lane, root = make_lane(self, FakeRunner(), lane_core.Clock())
        tool = root / "device_lock.py"
        tool.write_text(STUB_LOCK_TOOL)
        lane.lock_tool = tool
        lane.lock_dir = root / "device.lock"
        lane.python = sys.executable
        result = preflight(lane, "real-holder-run")
        self.addCleanup(lambda: lane.release_file_for("real-holder-run").write_text("real-holder-run"))
        self.assertEqual(result["status"], READY, result["notes"])
        self.assertEqual(lane_preflight.lock_owner_run(lane), "real-holder-run")
        time.sleep(1.5)
        self.assertEqual(lane_preflight.lock_owner_run(lane), "real-holder-run")  # still held
        self.assertTrue(lane_preflight.release_lock(lane))
        deadline = time.time() + 10
        while lane.lock_dir.exists() and time.time() < deadline:
            time.sleep(0.2)
        self.assertFalse(lane.lock_dir.exists())
        self.assertFalse(lane.release_file_for("real-holder-run").exists())
        pid = lane_core.load_session(lane)["holder_pid"]
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass


if __name__ == "__main__":
    unittest.main()
