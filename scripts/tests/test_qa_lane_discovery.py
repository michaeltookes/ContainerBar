#!/usr/bin/env python3
"""CB-137: status-item and panel discovery through the released app's AX tree."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

from qa_lane_fakes import FakeRunner, make_lane

import lane_core
from lane_discovery import (STATE_FILE, close_panel, find_status_item, open_panel, panel_region,
                            parse_ax_items, parse_frame)

RELEASED = "/Applications/ContainerBar.app/Contents/MacOS/ContainerBar"
HUNT = "/work/x/.prowl/DerivedData/Build/Products/Debug/ContainerBar.app/Contents/MacOS/ContainerBar"

# Recorded shape of the QA Mini's System Events output: the application menu is bar 1 (zero size),
# the status item is bar 2 (description ContainerBar, title is the running count).
AX_RELEASED = ("1|1|0|30|0|0|Apple|missing value|missing value\n1|2|0|30|0|0|ContainerBar|missing value|missing value\n"
               "2|1|1453|3|54|24|5|ContainerBar|5 of 6 containers running\n")
AX_HUNT = "2|1|1200|3|54|24|1|ContainerBar|1 of 1 containers running\n"
AX_NONE = "1|1|0|30|0|0|Apple|missing value|missing value\n1|2|0|30|0|0|ContainerBar|missing value|missing value\n"


def peek_json(*entries):
    controls = [{"title": "Control Center #%d" % n, "axDescription": "Item-0", "description": "com.apple.controlcenter",
                 "frame": [[1000 + n * 40, 0], [38, 30]]} for n in range(9)]
    named = [{"title": t, "axDescription": t, "description": "com.apple.controlcenter", "frame": [[x, 0], [54, 30]]}
             for t, x in entries]
    return json.dumps({"data": {"items": controls + named}})


class Fixture(unittest.TestCase):
    def setUp(self):
        self.runner = FakeRunner()
        self.lane, self.root = make_lane(self, self.runner, extra_env={"CBQA_PEEKABOO": "peekaboo"})
        self.run_dir = self.root / "run"
        self.pids = {100: RELEASED}
        self.ax = {100: AX_RELEASED}
        self.peek = peek_json()
        self.menu = ""               # AX menu frame, "" = no menu
        self.menu_opens_on = "click"  # "click", "axpress" or "never"
        self.state = {"clicked": False, "pressed": False}
        self.shot_ok = True
        self.runner.on("pgrep -x ContainerBar", lambda a: (0, "\n".join(str(p) for p in self.pids) + "\n"))
        self.runner.on("ps -o command=", lambda a: (0, self.pids[int(a[-1])] + "\n"))
        self.runner.on("peekaboo menubar list", lambda a: (0, self.peek))
        self.runner.on("peekaboo click", self.on_click)
        self.runner.on("peekaboo see", self.on_see)
        self.runner.on("osascript", self.on_osascript)

    def on_click(self, argv):
        self.state["clicked"] = True
        return 0, "{}"

    def on_see(self, argv):
        if self.shot_ok:
            Path(argv[argv.index("--path") + 1]).write_text("png")
        return (0, "{}") if self.shot_ok else (1, "")

    def on_osascript(self, argv):
        script = argv[2]
        if "click menu bar item" in script:
            self.state["pressed"] = True
            return 0, ""
        if "menu 1 of menu bar item" in script:
            opened = {"click": self.state["clicked"], "axpress": self.state["pressed"], "never": False}[self.menu_opens_on]
            return 0, (self.menu if opened else "")
        if "key code 53" in script:
            return 0, ""
        return 0, self.ax[int(argv[3])]

    def ran_peekaboo(self, verb):
        return [c for c in self.runner.calls if c[:2] == ["peekaboo", verb]]


class DiscoveryTests(Fixture):
    def test_parse_ax_items_and_frame(self):
        items = parse_ax_items(AX_RELEASED + "garbage\n")
        self.assertEqual(len(items), 3)
        self.assertEqual(items[2]["frame"], [1453, 3, 54, 24])
        self.assertEqual(items[2]["description"], "ContainerBar")
        self.assertEqual(parse_frame("1450|31|400|720"), [1450, 31, 400, 720])
        self.assertIsNone(parse_frame(""))
        self.assertIsNone(parse_frame("0|0|0|0"))

    def test_peekaboo_lists_the_item_peekaboo_path_used(self):
        self.peek = peek_json(("ContainerBar", 1440))
        code, lines, found = find_status_item(self.lane, self.run_dir)
        self.assertEqual(code, 0)
        self.assertEqual(lines[0], "found-by: peekaboo")
        self.assertEqual(found["frame"], [1440, 0, 54, 30])

    def test_peekaboo_misses_ax_has_it_ax_path_used(self):
        code, lines, found = find_status_item(self.lane, self.run_dir)
        self.assertEqual(code, 0)
        self.assertEqual(lines, ["found-by: ax", "frame: 1453,3,54,24"])
        self.assertEqual(found["pid"], 100)

    def test_application_menu_items_are_not_the_status_item(self):
        self.ax = {100: AX_NONE}
        code, lines, _ = find_status_item(self.lane, self.run_dir)
        self.assertEqual(code, 2)

    def test_neither_one_blocked_line_with_counts_dump_and_no_repeat(self):
        self.ax = {100: AX_NONE}
        code, lines, _ = find_status_item(self.lane, self.run_dir)
        self.assertEqual((code, len(lines)), (2, 1))
        self.assertTrue(lines[0].startswith("BLOCKED status-item-not-found menubar=9 ax=0"), lines[0])
        self.assertGreaterEqual(self.lane.clock.elapsed(), 10)  # polled for the 10 s budget
        dump = (self.run_dir / "ax-dump.txt").read_text()
        self.assertIn("menubar list: 9 entries, 0 match ContainerBar", dump)
        self.assertIn("1|2|0|30|0|0|ContainerBar", dump)
        self.assertEqual(lane_core.read_json(self.run_dir / STATE_FILE)["reason"], "status-item-not-found")
        # The next case of the same pass: blocked again, but no second BLOCKED line and no new look.
        calls = len(self.runner.calls)
        code, again, _ = find_status_item(self.lane, self.run_dir)
        self.assertEqual(code, 2)
        self.assertFalse(again[0].startswith("BLOCKED"))
        self.assertEqual(len(self.runner.calls), calls)

    def test_item_appearing_within_the_budget_is_found(self):
        answers = [AX_NONE, AX_NONE, AX_RELEASED]
        self.runner.on("osascript", lambda a: (0, answers.pop(0) if len(answers) > 1 else answers[0])
                       if "unix id" in a[2] and "position of mi" in a[2] else (0, ""))
        code, lines, _ = find_status_item(self.lane, self.run_dir)
        self.assertEqual((code, lines[0]), (0, "found-by: ax"))

    def test_two_candidates_not_tied_to_the_released_pid_blocked_with_both_lists(self):
        self.peek = peek_json(("ContainerBar", 900), ("ContainerBar", 1300))
        self.ax = {100: AX_NONE}
        code, lines, _ = find_status_item(self.lane, self.run_dir)
        self.assertEqual(code, 2)
        self.assertTrue(lines[0].startswith("BLOCKED status-item-ambiguous"), lines[0])
        dump = (self.run_dir / "ax-dump.txt").read_text()
        self.assertEqual(dump.count('"title": "ContainerBar"'), 2)

    def test_hunt_build_is_never_read_or_clicked(self):
        self.pids = {100: RELEASED, 200: HUNT}
        self.ax = {100: AX_RELEASED, 200: AX_HUNT}
        code, lines, found = find_status_item(self.lane, self.run_dir)
        self.assertEqual((code, found["pid"], found["frame"]), (0, 100, [1453, 3, 54, 24]))
        self.assertFalse(any(c[:1] == ["osascript"] and c[3] == "200" for c in self.runner.calls))

    def test_hunt_build_alone_is_not_the_released_app(self):
        self.pids = {200: HUNT}
        self.ax = {200: AX_HUNT}
        self.peek = peek_json(("ContainerBar", 1190))
        code, lines, _ = find_status_item(self.lane, self.run_dir)
        self.assertEqual(code, 2)
        self.assertIn("BLOCKED", lines[0])

    def test_hunt_running_with_a_peekaboo_entry_and_no_ax_tie_is_blocked(self):
        self.pids = {100: RELEASED, 200: HUNT}
        self.ax = {100: AX_NONE, 200: AX_HUNT}
        self.peek = peek_json(("ContainerBar", 1190))
        code, lines, _ = find_status_item(self.lane, self.run_dir)
        self.assertEqual(code, 2)
        self.assertTrue(lines[0].startswith("BLOCKED status-item-ambiguous"), lines[0])


class PanelTests(Fixture):
    def test_click_centre_opens_and_captures_the_ax_menu_frame(self):
        self.menu = "1450|31|400|720"
        shot = self.root / "02-panel-open.png"
        code, lines = open_panel(self.lane, self.run_dir, shot)
        self.assertEqual(code, 0)
        self.assertEqual(self.ran_peekaboo("click")[0][3], "1480,15")
        self.assertIn("opened-by: click", lines)
        self.assertIn("panel-capture: ax-menu", lines)
        see = self.ran_peekaboo("see")[0]
        self.assertEqual(see[see.index("--region") + 1], "1450,31,400,720")
        self.assertTrue(shot.exists())
        self.assertFalse(self.state["pressed"])

    def test_axpress_when_the_click_does_not_open_it(self):
        self.menu, self.menu_opens_on = "1450|31|400|720", "axpress"
        code, lines = open_panel(self.lane, self.run_dir, self.root / "p.png")
        self.assertEqual(code, 0)
        self.assertIn("opened-by: axpress", lines)

    def test_panel_not_capturable_is_one_blocked_line(self):
        self.menu_opens_on = "never"
        code, lines = open_panel(self.lane, self.run_dir, self.root / "p.png")
        self.assertEqual((code, len(lines)), (2, 1))
        self.assertTrue(lines[0].startswith("BLOCKED panel-not-capturable"), lines[0])
        code, again = open_panel(self.lane, self.run_dir, self.root / "p.png")
        self.assertEqual(code, 2)
        self.assertFalse(again[0].startswith("BLOCKED"))

    def test_capture_failure_is_panel_not_capturable(self):
        self.menu, self.shot_ok = "1450|31|400|720", False
        code, lines = open_panel(self.lane, self.run_dir, self.root / "p.png")
        self.assertEqual(code, 2)
        self.assertIn("panel-not-capturable", lines[0])

    def test_status_item_not_found_stops_before_any_click(self):
        self.ax = {100: AX_NONE}
        code, lines = open_panel(self.lane, self.run_dir, self.root / "p.png")
        self.assertEqual(code, 2)
        self.assertEqual(self.ran_peekaboo("click"), [])

    def test_region_fallback_sits_under_the_item(self):
        self.assertEqual(panel_region([1453, 3, 54, 24], None), [1450, 31, 400, 720])
        self.assertEqual(panel_region([1453, 3, 54, 24], [1, 2, 3, 4]), [1, 2, 3, 4])

    def test_close_panel_sends_escape(self):
        close_panel(self.lane)
        self.assertTrue(any("key code 53" in " ".join(c) for c in self.runner.calls))


if __name__ == "__main__":
    unittest.main()
