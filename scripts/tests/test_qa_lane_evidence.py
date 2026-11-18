#!/usr/bin/env python3
"""CB-138: TC-CB-02 evidence: status-item strip, hunt lines, verdict."""
from __future__ import annotations

import unittest
from pathlib import Path

from qa_lane_fakes import FakeRunner, make_lane

from lane_evidence import (AX_FILE, HUNT_FILE, PANEL, STRIP, capture_status_item, hunt_checks, parse_hunt,
                           strip_region, verdict)
from test_qa_lane_discovery import AX_RELEASED, Fixture, peek_json


class StripRegionTests(unittest.TestCase):
    def test_frame_plus_four_px_margin(self):
        self.assertEqual(strip_region([1495, 3, 54, 24]), [1491, -1, 62, 32])

    def test_never_wider_than_frame_plus_8_or_taller_than_32(self):
        for frame in ([1495, 3, 54, 24], [100, 0, 40, 30], [10, 5, 200, 50], [0, 0, 20, 10]):
            x, y, w, h = strip_region(frame)
            self.assertLessEqual(w, frame[2] + 8)
            self.assertLessEqual(h, 32)

    def test_kept_on_its_display(self):
        x, y, w, h = strip_region([1495, 3, 54, 24], [0, 0, 1500, 900])
        self.assertGreaterEqual(y, 0)
        self.assertLessEqual(x + w, 1500)


class CaptureTests(Fixture):
    def setUp(self):
        super().setUp()
        self.case = self.root / "case"

    def strip_calls(self):
        return [c for c in self.ran_peekaboo("see") if str(self.case / STRIP) in c]

    def test_strip_is_a_region_capture_of_the_frame_plus_margin_and_ax_value_recorded(self):
        code, lines = capture_status_item(self.lane, self.run_dir, self.case)
        self.assertEqual(code, 0, lines)
        call = self.strip_calls()[0]
        self.assertEqual(call[call.index("--region") + 1], "1449,-1,62,32")
        self.assertTrue((self.case / STRIP).exists())
        self.assertIn("ax-value: 5 of 6 containers running", (self.case / AX_FILE).read_text())

    def test_frame_off_every_display_blocks_with_the_dump(self):
        self.display_out = "5000|0|1920|1080\n"
        code, lines = capture_status_item(self.lane, self.run_dir, self.case)
        self.assertEqual(code, 2)
        self.assertTrue(lines[0].startswith("BLOCKED status-item-frame-missing"), lines[0])
        self.assertTrue((self.run_dir / "ax-dump.txt").exists())
        self.assertEqual(self.strip_calls(), [])
        self.assertEqual(verdict(self.run_dir, self.case)[0], 2)
        self.assertIn("status-item-frame-missing", verdict(self.run_dir, self.case)[1])

    def test_empty_ax_value_is_not_recorded(self):
        self.ax = {100: "2|1|1453|3|54|24|5|ContainerBar|missing value\n"}
        code, lines = capture_status_item(self.lane, self.run_dir, self.case)
        self.assertEqual(code, 0)
        self.assertIn("ax-value: missing", lines)
        self.assertFalse((self.case / AX_FILE).exists())

    def test_peekaboo_only_item_still_gets_a_strip(self):
        self.ax = {100: "1|1|0|30|0|0|Apple|missing value|missing value\n"}
        self.peek = peek_json(("ContainerBar", 1440))
        code, lines = capture_status_item(self.lane, self.run_dir, self.case)
        self.assertEqual(code, 0, lines)
        self.assertTrue((self.case / STRIP).exists())
        self.assertFalse((self.case / AX_FILE).exists())


class HuntTests(Fixture):
    def test_none_absent_and_fixture_lines(self):
        self.override("defaults read", lambda a: (1, ""))
        code, lines = hunt_checks(self.lane, self.root / "case", "absent")
        self.assertEqual(lines, ["hunt-process: none", "hunt-sparkle: absent", "hunt-fixture-text: absent"])
        self.assertEqual((self.root / "case" / HUNT_FILE).read_text().splitlines(), lines)

    def test_hunt_process_pid_and_sparkle_value(self):
        self.pids[200] = HUNT
        self.override("defaults read", lambda a: (0, "2026-11-18 07:08:25 +0000\n"))
        _, lines = hunt_checks(self.lane, self.root / "case", "present")
        self.assertEqual(lines[0], "hunt-process: 200")
        self.assertEqual(lines[1], "hunt-sparkle: 2026-11-18 07:08:25 +0000")
        self.assertEqual(lines[2], "hunt-fixture-text: present")

    def test_missing_fixture_reading_is_unknown_and_parse_requires_all_three(self):
        _, lines = hunt_checks(self.lane, self.root / "case", "")
        self.assertEqual(lines[2], "hunt-fixture-text: unknown")
        self.assertEqual(len(parse_hunt("hunt-process: none\nhunt-sparkle: absent\n")), 2)


HUNT = "/x/Debug/ContainerBar.app/Contents/MacOS/ContainerBar"


class VerdictTests(Fixture):
    def setUp(self):
        super().setUp()
        self.case = self.root / "case"
        self.override("defaults read", lambda a: (1, ""))
        capture_status_item(self.lane, self.run_dir, self.case)
        (self.case / PANEL).write_text("panel")
        hunt_checks(self.lane, self.case, "absent")

    def test_all_four_items_present_is_pass_even_with_the_hunt_domain_missing(self):
        self.assertEqual(verdict(self.run_dir, self.case), (0, "PASS"))

    def test_each_missing_item_is_evidence_incomplete_naming_it(self):
        for name, item in ((STRIP, STRIP), (PANEL, PANEL), (AX_FILE, "ax-value"), (HUNT_FILE, "hunt-checks")):
            path = self.case / name
            saved = path.read_text() if name != STRIP else "png"
            path.unlink()
            code, line = verdict(self.run_dir, self.case)
            self.assertEqual((code, line), (2, "BLOCKED evidence-incomplete %s" % item))
            path.write_text(saved)
        self.assertEqual(verdict(self.run_dir, self.case)[0], 0)

    def test_oversized_strip_record_is_not_evidence(self):
        (self.case / "status-item-capture.json").write_text('{"frame": [0,0,54,24], "region": [0,0,200,40]}')
        self.assertEqual(verdict(self.run_dir, self.case), (2, "BLOCKED evidence-incomplete %s" % STRIP))

    def test_fixture_text_present_is_fail_p1(self):
        hunt_checks(self.lane, self.case, "present")
        code, line = verdict(self.run_dir, self.case)
        self.assertEqual(code, 1)
        self.assertTrue(line.startswith("FAIL P1"))

    def test_unknown_fixture_reading_is_incomplete(self):
        hunt_checks(self.lane, self.case, "")
        self.assertEqual(verdict(self.run_dir, self.case), (2, "BLOCKED evidence-incomplete hunt-checks"))


if __name__ == "__main__":
    unittest.main()
