#!/usr/bin/env python3
"""CB-105 story 6 AC2-AC4 and CB-110/CB-112: CI wait, desktop lock, deadline, marker recovery.

Run: python3 -m unittest discover -s scripts/tests -p 'test_qa_lane*.py'
"""
from __future__ import annotations

import json
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
        self.assertEqual(seen, [60.0 * i for i in range(9)])  # T0, T0+60 ... T0+480

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


if __name__ == "__main__":
    unittest.main()
