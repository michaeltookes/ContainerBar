#!/usr/bin/env python3
"""CB-135: the recipe passes the lock token, and resign-gui.sh carries it into a one-shot gui/501 job."""
from __future__ import annotations

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from qa_lane_fakes import LANE_DIR

RECIPE = Path(LANE_DIR, "CONTAINERBAR_QA.md").read_text()
RESIGN_MD = Path(LANE_DIR, "RESIGN.md").read_text()
WRAPPER = os.path.join(LANE_DIR, "resign-gui.sh")

FAKE_LAUNCHCTL = r'''#!/usr/bin/env python3
import os, plistlib, subprocess, sys
log = os.environ["FAKE_LAUNCHCTL_LOG"]
open(log, "a").write(" ".join(sys.argv[1:2]) + "\n")
if sys.argv[1] == "bootstrap":
    d = plistlib.load(open(sys.argv[3], "rb"))
    env = dict(os.environ, **d["EnvironmentVariables"])
    subprocess.run(d["ProgramArguments"], env=env, check=False)
'''


class RecipeTokenTests(unittest.TestCase):
    def test_every_install_invocation_carries_the_token(self):
        for name, text in (("recipe", RECIPE), ("RESIGN.md", RESIGN_MD)):
            for line in text.splitlines():
                for m in re.finditer(r"(\S*)\s*bash tools/containerbar-qa/resign(-gui)?\.sh\s+(\S+)", line):
                    if m.group(3).startswith("--provenance"):
                        continue
                    self.assertIn('CBQA_LOCK_TOKEN="$TOKEN"', line, (name, line))
        self.assertIn('CBQA_LOCK_TOKEN="$TOKEN" bash tools/containerbar-qa/resign-gui.sh', RECIPE)

    def test_keychain_helper_never_called_without_path(self):
        for text in (RECIPE, RESIGN_MD):
            for m in re.finditer(r"keychain_unlocked\.py(`?)\s*(\S*)", text):
                tail = text[m.start():m.start() + 160]
                if re.search(r"<login keychain path>|login\.keychain-db|CBQA_KEYCHAIN|\"\$keychain\"|exit", tail):
                    continue
                self.fail("keychain_unlocked.py call without a keychain path: " + tail)

    def test_wrapper_is_installed(self):
        self.assertIn("resign-gui.sh", Path(LANE_DIR, "install.sh").read_text())


class WrapperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        r = Path(self.tmp.name)
        self.ws = r / "ws"; self.ws.mkdir()
        (r / "launchctl").write_text(FAKE_LAUNCHCTL); (r / "launchctl").chmod(0o755)
        # Fake lane dir: the real wrapper next to a stub resign.sh that echoes its inputs and exits with a chosen code.
        self.lane = r / "lane"; self.lane.mkdir()
        (self.lane / "resign-gui.sh").write_text(Path(WRAPPER).read_text())
        (self.lane / "resign.sh").write_text('#!/bin/bash\necho "args=$*"\n[ -n "${CBQA_LOCK_TOKEN:-}" ] && echo token-present || echo token-missing\nexit "${STUB_RC:-0}"\n')
        self.log = r / "launchctl.log"
        self.env = dict(os.environ, CBQA_WORKSPACE=str(self.ws), CBQA_LAUNCHCTL=str(r / "launchctl"),
                        FAKE_LAUNCHCTL_LOG=str(self.log), CBQA_UID="501", CBQA_RESIGN_TIMEOUT="10")

    def run_wrapper(self, *args, **env):
        return subprocess.run(["/bin/bash", str(self.lane / "resign-gui.sh"), *args],
                              env=dict(self.env, **env), capture_output=True, text=True)

    def test_token_reaches_job_and_exit_code_is_unchanged(self):
        for rc in (0, 6, 7):
            done = self.run_wrapper("/x/Cand.app", "abc123", CBQA_LOCK_TOKEN="pass.tok-1", STUB_RC=str(rc))
            self.assertEqual(done.returncode, rc, done.stderr)
            self.assertIn("args=/x/Cand.app abc123", done.stdout)
            self.assertIn("token-present", done.stdout)
            self.assertNotIn("pass.tok-1", done.stdout + done.stderr)

    def test_one_shot_agent_is_booted_out_and_plist_removed(self):
        self.run_wrapper("/x/Cand.app", "abc", CBQA_LOCK_TOKEN="t1")
        self.assertEqual(self.log.read_text().split(), ["bootstrap", "bootout"])
        base = self.ws / "artifacts" / "containerbar-qa" / "resign-gui"
        self.assertEqual(list(base.glob("**/*.plist")), [])

    def test_empty_token_is_passed_through_for_resign_to_block(self):
        done = self.run_wrapper("/x/Cand.app", "abc", STUB_RC="7")
        self.assertEqual(done.returncode, 7)
        self.assertIn("token-missing", done.stdout)

    def test_bad_token_characters_are_refused(self):
        done = self.run_wrapper("/x/Cand.app", "abc", CBQA_LOCK_TOKEN="a</string>b")
        self.assertEqual(done.returncode, 64)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
