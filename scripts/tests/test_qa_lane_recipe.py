#!/usr/bin/env python3
"""CB-101: the CONTAINERBAR_QA.md recipe and the installer step that copies it."""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from qa_lane_fakes import LANE_DIR

RECIPE = Path(LANE_DIR, "CONTAINERBAR_QA.md")


def shell_blocks(text: str):
    return re.findall(r"^```sh\n(.*?)^```$", text, flags=re.S | re.M)


class RecipeTests(unittest.TestCase):
    def setUp(self):
        self.text = RECIPE.read_text()

    def test_recipe_stays_under_300_lines(self):
        self.assertLess(len(self.text.splitlines()), 300)

    def test_embedded_commands_parse(self):
        blocks = shell_blocks(self.text)
        self.assertGreaterEqual(len(blocks), 4)
        for shell in ("/bin/bash", "/bin/zsh"):
            if not os.path.exists(shell):
                continue
            for block in blocks:
                done = subprocess.run([shell, "-n"], input=block, capture_output=True, text=True)
                self.assertEqual(done.returncode, 0, "%s: %s\n%s" % (shell, done.stderr, block))

    def test_token_is_passed_to_every_lock_command(self):
        for cmd in ("normalise", "case-gate", "release"):
            calls = re.findall(r"cbqa_lane\.py %s[^`\n]*" % cmd, self.text)
            self.assertTrue(calls, cmd)
            for call in calls:
                self.assertIn('--token "$TOKEN"', call, call)
        self.assertNotIn("session.json", self.text.replace("from `session.json`", ""))

    def test_ssh_cases_blocked_with_exact_reason(self):
        self.assertIn("blocked local-network-denied (CB-116)", self.text)
        section = self.text.split("### SSH cases", 1)[1].split("## Stop and ask", 1)[0]
        for case in ("03", "04", "05", "06", "07", "09", "10", "15", "16", "17"):
            self.assertIn("TC-CB-%s " % case, section)

    def test_gui_done_only_after_ui_restore_and_before_release(self):
        restore = self.text.split("## Restore and release", 1)[1].split("## Report and post", 1)[0]
        self.assertIn("Only if step 2 succeeded", restore)
        self.assertLess(restore.index("gui-done"), restore.index("release --token"))

    def test_no_private_values(self):
        self.assertIsNone(re.search(r"\b\d{1,3}(\.\d{1,3}){3}\b", self.text))
        self.assertNotRegex(self.text, r"channel:\d|/Users/[a-z]")


class InstallCopiesRecipeTests(unittest.TestCase):
    def setUp(self):
        if not os.path.exists("/bin/zsh") or not os.path.exists("/usr/bin/plutil"):
            self.skipTest("needs zsh and macOS plutil")
        self.root = Path(tempfile.mkdtemp(prefix="cbqa-install-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        self.ws = self.root / "ws"
        self.env = dict(os.environ, HOME=str(self.root / "home"), CBQA_WORKSPACE=str(self.ws))

    def test_dry_run_plans_the_recipe_copy_and_writes_nothing(self):
        done = subprocess.run(["/bin/zsh", os.path.join(LANE_DIR, "install.sh")], env=self.env,
                              capture_output=True, text=True, timeout=60)
        self.assertEqual(done.returncode, 0, done.stderr)
        expected = "dry-run: cp %s %s" % (RECIPE, self.ws / "CONTAINERBAR_QA.md")
        lines = done.stdout.splitlines()
        self.assertIn(expected, [line.replace("\\ ", " ") for line in lines])
        self.assertFalse((self.ws / "CONTAINERBAR_QA.md").exists())


if __name__ == "__main__":
    unittest.main()
