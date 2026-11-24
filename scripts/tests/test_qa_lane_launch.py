#!/usr/bin/env python3
"""CB-142: the released app is running (and ready) before discovery; mocked clock, pgrep, ps and open."""
from __future__ import annotations

import unittest
from pathlib import Path

from test_qa_lane_discovery import AX_NONE, AX_RELEASED, HUNT, Fixture

import lane_core
from lane_discovery import STATE_FILE
from lane_launch import ensure_running, find_with_launch, launch_app
from lane_restore import gui_done

RECIPE = Path(__file__).resolve().parents[1] / "qa-lane" / "CONTAINERBAR_QA.md"


class LaunchFixture(Fixture):
    def setUp(self):
        super().setUp()
        self.pids = {}                # nothing running
        self.ax = {}
        self.opens = []               # one answer per open -a call: (rc, out); last repeats
        self.open_answers = [(0, "")]
        self.appears_after_open = 3.0   # seconds from the successful open until the process exists
        self.opened_at = None
        self.runner.on("open -a", self.on_open)
        self.runner.handlers.insert(0, ("pgrep -x ContainerBar", self.pgrep))
        self.runner.on("log show", lambda a: (0, "\n".join("line %d" % n for n in range(80))))

    def on_open(self, argv):
        self.opens.append(argv)
        rc, out = self.open_answers[min(len(self.opens), len(self.open_answers)) - 1]
        if rc == 0:
            self.opened_at = self.lane.clock.now()
        return rc, out

    def pgrep(self, argv):
        if self.opened_at is not None and self.lane.clock.now() - self.opened_at >= self.appears_after_open:
            self.pids[300] = self.released()
            self.ax[300] = AX_RELEASED
        return (0, "\n".join(str(p) for p in self.pids) + "\n") if self.pids else (1, "")


class LaunchTests(LaunchFixture):
    def test_not_running_is_launched_and_the_pass_goes_on(self):
        code, lines, found = find_with_launch(self.lane, self.run_dir)
        self.assertEqual(code, 0)
        self.assertEqual(lines[0], "app-launch: launched (was not running) pid 300")
        self.assertEqual(lines[1], "found-by: ax")
        self.assertEqual(self.opens, [["open", "-a", self.lane.app_path]])
        self.assertEqual(found["pid"], 300)

    def test_already_running_is_untouched(self):
        self.pids = {100: self.released()}
        self.ax = {100: AX_RELEASED}
        code, lines, _ = find_with_launch(self.lane, self.run_dir)
        self.assertEqual((code, lines[0]), (0, "app-launch: already running pid 100"))
        self.assertEqual(self.opens, [])

    def test_hunt_build_only_is_left_alone_and_released_is_launched(self):
        self.pids = {200: HUNT}
        code, lines = ensure_running(self.lane, self.run_dir)
        self.assertEqual((code, lines), (0, ["app-launch: launched (was not running) pid 300"]))
        self.assertEqual(len(self.opens), 1)
        self.assertIn(200, self.pids)
        self.assertEqual([c for c in self.runner.calls if c[0] in ("kill", "pkill", "osascript")], [])

    def test_open_failing_twice_blocks_app_launch_failed_with_evidence(self):
        self.open_answers = [(1, "boom"), (1, "boom")]
        code, lines, found = find_with_launch(self.lane, self.run_dir)
        self.assertEqual((code, found), (2, None))
        self.assertIn("relaunch: retried after 1", lines)
        blocked = [l for l in lines if l.startswith("BLOCKED")]
        self.assertEqual(len(blocked), 1)
        self.assertTrue(blocked[0].startswith("BLOCKED app-launch-failed 1 "), blocked[0])
        self.assertNotIn("status-item-not-found", " ".join(lines))
        self.assertEqual(lane_core.read_json(self.run_dir / STATE_FILE)["reason"], "app-launch-failed")
        self.assertEqual(len((self.run_dir / "app-launch-log.txt").read_text().splitlines()), 50)
        self.assertTrue((self.run_dir / "ax-dump.txt").read_text().startswith("released pids: \n"))
        # every later UI case is blocked the same way, with no second BLOCKED line and no new launch
        code, again, _ = find_with_launch(self.lane, self.run_dir)
        self.assertEqual(code, 2)
        self.assertFalse(again[0].startswith("BLOCKED"))
        self.assertEqual(len(self.opens), 2)

    def test_no_process_within_ten_seconds_is_a_timeout_block(self):
        self.appears_after_open = 99
        code, lines = ensure_running(self.lane, self.run_dir)
        self.assertEqual(code, 2)
        self.assertTrue(lines[0].startswith("BLOCKED app-launch-failed timeout"), lines[0])
        self.assertGreaterEqual(self.lane.clock.elapsed(), 10)
        self.assertLess(self.lane.clock.elapsed(), 12)

    def test_error_600_then_success_is_one_retry(self):
        self.open_answers = [(1, "error -600 procNotFound"), (0, "")]
        code, lines = ensure_running(self.lane, self.run_dir)
        self.assertEqual(code, 0)
        self.assertEqual(len(self.opens), 2)
        self.assertEqual(lines[0], "relaunch: retried after -600")
        self.assertEqual(lines[1], "app-launch: launched (was not running) pid 300")

    def test_error_600_twice_blocks_with_600(self):
        self.open_answers = [(1, "-600"), (1, "-600")]
        code, lines = ensure_running(self.lane, self.run_dir)
        self.assertEqual(code, 2)
        self.assertEqual(len(self.opens), 2)
        self.assertTrue(lines[-1].startswith("BLOCKED app-launch-failed -600 "), lines[-1])

    def test_retry_waits_for_the_old_pid_to_exit_up_to_ten_seconds(self):
        self.pids = {100: self.released()}
        self.open_answers = [(1, "-600"), (0, "")]
        gone_at = self.lane.clock.now() + 4

        def pgrep(argv):
            if self.lane.clock.now() >= gone_at:
                self.pids.pop(100, None)
            return (0, "\n".join(str(p) for p in self.pids) + "\n") if self.pids else (1, "")
        self.override("pgrep -x ContainerBar", pgrep)
        notes = []
        before = self.lane.clock.now()
        self.assertEqual(launch_app(self.lane, notes, [100]), (True, ""))
        self.assertGreaterEqual(self.lane.clock.now() - before, 4)
        self.assertEqual(notes, ["relaunch: retried after -600"])
        # an old process that never exits does not hold the retry past ten seconds
        self.pids = {100: self.released()}
        self.override("pgrep -x ContainerBar", lambda a: (0, "100\n"))
        self.opens.clear()
        before = self.lane.clock.now()
        launch_app(self.lane, [], [100])
        self.assertLessEqual(self.lane.clock.now() - before, 11)
        self.assertEqual(len(self.opens), 2)

    def test_pid_present_but_item_missing_stays_status_item_not_found_with_pids_in_dump(self):
        self.pids = {100: self.released()}
        self.ax = {100: AX_NONE}
        code, lines, _ = find_with_launch(self.lane, self.run_dir)
        self.assertEqual(code, 2)
        blocked = [l for l in lines if l.startswith("BLOCKED")]
        self.assertEqual(len(blocked), 1)
        self.assertTrue(blocked[0].startswith("BLOCKED status-item-not-found"), blocked[0])
        self.assertIn("released pids: 100\n", (self.run_dir / "ax-dump.txt").read_text())

    def test_launched_but_item_never_appears_is_status_item_not_found(self):
        self.ax_after = AX_NONE
        self.runner.handlers.insert(0, ("pgrep -x ContainerBar", self.pgrep))
        orig = self.pgrep

        def pgrep(argv):
            r = orig(argv)
            if 300 in self.pids:
                self.ax[300] = AX_NONE
            return r
        self.override("pgrep -x ContainerBar", pgrep)
        code, lines, _ = find_with_launch(self.lane, self.run_dir)
        self.assertEqual(code, 2)
        self.assertTrue(any(l.startswith("BLOCKED status-item-not-found") for l in lines), lines)
        self.assertIn("released pids: 300\n", (self.run_dir / "ax-dump.txt").read_text())


class GuiDoneTests(LaunchFixture):
    def flag(self):
        lane_core.write_json(self.lane.gui_flag, {"since": 1})

    def test_no_process_withholds_and_keeps_the_flag(self):
        self.flag()
        ok, notes = gui_done(self.lane, self.run_dir)
        self.assertFalse(ok)
        self.assertIn("withheld", notes[0])
        self.assertTrue(self.lane.gui_flag.exists())

    def test_process_without_status_item_withholds(self):
        self.flag()
        self.pids = {100: self.released()}
        self.ax = {100: AX_NONE}
        ok, notes = gui_done(self.lane, self.run_dir)
        self.assertFalse(ok)
        self.assertIn("pid 100, no status item", notes[0])
        self.assertTrue(self.lane.gui_flag.exists())

    def test_process_plus_status_item_clears_without_peekaboo_window_inventory(self):
        self.flag()
        self.pids = {100: self.released()}
        self.ax = {100: AX_RELEASED}
        ok, notes = gui_done(self.lane, self.run_dir)
        self.assertEqual((ok, notes), (True, ["gui-cleanup-pending cleared"]))
        self.assertFalse(self.lane.gui_flag.exists())
        self.assertEqual([c for c in self.runner.calls if "windows" in " ".join(c)], [])


class RecipeTests(unittest.TestCase):
    def test_recipe_uses_the_helper_and_stays_within_320_lines(self):
        text = RECIPE.read_text()
        self.assertLessEqual(len(text.splitlines()), 320)
        tc02 = text.split("**TC-CB-02 Status item", 1)[1].split("**TC-CB-33", 1)[0]
        self.assertIn("first launches the released app", tc02)
        self.assertIn("app-launch-failed", tc02)
        self.assertNotIn("open /Applications/ContainerBar.app", text)
        self.assertIn('gui-done --run-dir "<run>"', text)
        self.assertIn('launch-app --run-dir "<run>"', text.split("**TC-CB-08", 1)[1])


if __name__ == "__main__":
    unittest.main()
