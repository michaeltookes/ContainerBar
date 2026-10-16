#!/usr/bin/env python3
"""CB-101: the CONTAINERBAR_QA.md recipe and the installer step that copies it."""
from __future__ import annotations

import os
import re
from shlex import quote as shlex_quote
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

    def test_workspace_root_comes_from_cbqa_workspace(self):
        # Codex round 1: never hardcode the default workspace; resolve it like Lane and install.sh.
        default = "$HOME/.openclaw/workspace"
        fallback = '"${CBQA_WORKSPACE:-%s}"' % default
        self.assertEqual(self.text.count(default), self.text.count(fallback))
        cds = re.findall(r"^cd .*$", "\n".join(shell_blocks(self.text)), flags=re.M)
        self.assertGreaterEqual(len(cds), 4)
        for line in cds:
            self.assertEqual(line, "cd " + fallback)

    def test_authority_read_with_verbose_codesign(self):
        self.assertIn("codesign -dv --verbose=4 \"$APP\" 2>&1 | grep '^Authority='", self.text)
        self.assertNotRegex(self.text, r"codesign -dv \"")

    def test_local_network_gate_after_launch_checks(self):
        gate = self.text.index("**Local Network gate (CB-116).**")
        self.assertLess(self.text.index("**TC-CB-02 Status item"), gate)
        self.assertLess(gate, self.text.index("**TC-CB-14 Check for Updates"))
        self.assertLess(self.text.index("## Every case"), gate)

    def test_logs_fallbacks_name_button_and_row(self):
        self.assertIn("button `Logs`", self.text)
        self.assertIn("the row button labelled with the container name", self.text)

    def block_with(self, needle):
        found = [b for b in shell_blocks(self.text) if needle in b]
        self.assertEqual(len(found), 1, needle)
        return found[0]

    def test_cask_version_is_the_quoted_value(self):
        # Codex round 2 (bot P1): compare the version string, not the whole declaration.
        line = [l for l in self.text.splitlines() if "containerbar.rb" in l and l.startswith("curl")][0]
        pipeline = line.split("|", 1)[1]
        cask = 'cask "containerbar" do\n  version "2.0.4"\n  sha256 "abc"\nend\n'
        done = subprocess.run(["/bin/bash", "-c", pipeline], input=cask, capture_output=True, text=True)
        self.assertEqual(done.stdout, "2.0.4\n", done.stderr)

    def run_gate(self, log_lines, build):
        block = self.block_with("local-network-grants.log")
        block = re.sub(r"BUILD='[^']*'", "BUILD='%s'" % build, block)
        with tempfile.TemporaryDirectory() as ws:
            Path(ws, "qa", "containerbar").mkdir(parents=True)
            Path(ws, "qa", "containerbar", "local-network-grants.log").write_text("".join(
                line + "\n" for line in log_lines))
            env = dict(os.environ, CBQA_WORKSPACE=ws)
            done = subprocess.run(["/bin/bash", "-c", block], env=env, capture_output=True, text=True)
        return done.stdout.strip()

    def test_developer_id_grant_covers_every_release(self):
        # Codex round 2 (bot P1): a Developer ID grant is not tied to one release.
        log = ["2026-10-17 | developer-id | - | michael"]
        self.assertEqual(self.run_gate(log, "2.0.4-7"), "gate-open")
        self.assertEqual(self.run_gate(log, "2.0.5-8"), "gate-open")

    def test_adhoc_grant_covers_only_its_build(self):
        log = ["2026-10-17 | adhoc | 2.0.5-8 | michael"]
        self.assertEqual(self.run_gate(log, "2.0.5-8"), "gate-open")
        self.assertEqual(self.run_gate(log, "2.0.5-9"), "gate-closed")
        self.assertEqual(self.run_gate([], "2.0.5-8"), "gate-closed")

    def test_connection_errors_are_redacted(self):
        # Codex round 2 (bot P2): no address or socket path reaches report.md.
        block = self.block_with("printf")
        samples = {
            "ssh: connect to host 192.168.1.20 port 22: Connection refused":
                "ssh: connect to host <address> port 22: Connection refused",
            "ssh: connect to host fe80::1%en0 port 22: No route to host":
                "ssh: connect to host <address> port 22: No route to host",
            "Could not reach [2001:db8::5]:22": "Could not reach <address>:22",
            "No such file /Users/qa/qa/containerbar/podman.sock": "No such file <socket>",
            # Round 3: DNS names, key files and home paths.
            "ssh: connect to host qa-box.lan port 22: Operation timed out":
                "ssh: connect to host <host> port 22: Operation timed out",
            "ssh: Could not resolve hostname qa-box.lan: nodename nor servname provided, or not known":
                "ssh: Could not resolve hostname <host>: nodename nor servname provided, or not known",
            'Load key "/Users/qa/.ssh/cbqa_tunnel_ed25519": invalid format':
                'Load key "<keyfile>": invalid format',
            "Warning: Identity file /Users/qa/.ssh/cbqa_tunnel_ed25519 not accessible: No such file or directory.":
                "Warning: Identity file <path> not accessible: No such file or directory.",
            "Permission denied reading /home/cbqa-fwd/.ssh/config": "Permission denied reading <path>",
            "no such identity: ~/.ssh/cbqa_ctl_ed25519": "no such identity: <path>",
        }
        for raw, want in samples.items():
            script = re.sub(r"ERR='[^']*'", "ERR=%s" % shlex_quote(raw), block)
            done = subprocess.run(["/bin/bash", "-c", script], capture_output=True, text=True)
            self.assertEqual(done.stdout.strip(), want, done.stderr)

    def test_unexpected_blocked_case_makes_the_run_blocked(self):
        # Codex round 2 (P2): only the CB-116 gate and predicted blocks are exempt.
        verdict = self.text.split("Verdict:", 1)[1].split("Final reply", 1)[0]
        self.assertIn("any case or step is blocked", verdict)
        self.assertIn("`forward-failed`", verdict)
        self.assertIn("`blocked local-network-denied (CB-116)` while the gate is closed", verdict)
        self.assertIn("known-failures table predicts", verdict)

    def test_signature_failure_launches_nothing(self):
        # Round 3 (bot P1): a failed signing check must not lead to launching the app.
        case = self.text.split("**TC-CB-01", 1)[1].split("**TC-CB-02", 1)[0]
        self.assertIn("Launch nothing", case)
        self.assertIn("`blocked signature-failed`", case)
        self.assertIn("start only after all three signature checks passed", case)
        restore = self.text.split("## Restore and release", 1)[1].split("## Report and post", 1)[0]
        self.assertIn("skipped after `signature-failed`", restore)
        self.assertIn("`signature-failed`", self.text.split("Blocked reasons:", 1)[1])

    def test_launch_is_gated_on_the_authority_too(self):
        # Final round (bot P1): a valid signature by another Developer ID must not launch.
        case = " ".join(self.text.split("**TC-CB-01", 1)[1].split("**TC-CB-02", 1)[0].split())
        self.assertIn("or the first Authority line is not exactly `CBQA_DEVELOPER_ID_AUTHORITY`", case)
        self.assertIn("`authority-mismatch`", case)
        self.assertIn("naming the check or the mismatch", case)
        self.assertIn("start only after all three signature checks passed and the Authority line matched",
                      case)
        failure = case.split("**A codesign, spctl or stapler check fails", 1)[1]
        self.assertIn("Launch nothing", failure)
        self.assertIn("`blocked signature-failed`", failure)

    def test_lock_not_owned_skips_the_restore(self):
        # Round 3 (bot P1): without the lock the pass must not touch the desktop.
        gate = self.text.split("`BLOCKED time-budget lock-not-owned`", 1)[1].split("### Runnable", 1)[0]
        self.assertIn("skip the whole restore", gate)
        for step in ("no restore script", "no UI", "no `gui-done`", 'release --token "$TOKEN"` once',
                     "left to the owning pass"):
            self.assertIn(step, gate.replace("\n", " "))
        self.assertIn("## Restore and release (always, except after `lock-not-owned`)", self.text)

    def test_socket_error_case_takes_no_screenshot(self):
        # Round 3 (bot P2): the expanded socket path names the account.
        case = self.text.split("**TC-CB-12", 1)[1].split("**TC-CB-11", 1)[0]
        self.assertIn("no screenshot", case)
        self.assertNotIn(".png", case)
        # Final round (bot P2): the redacted text is the step's asset.
        self.assertIn("`assets/TC-CB-12/01-socket-error.txt`", case)
        self.assertIn("accepted evidence", case)
        evidence = " ".join(self.text.split("## Evidence", 1)[1].split("## Step 0", 1)[0].split())
        self.assertIn("cannot be kept for privacy, the step's asset is `NN-<slug>.txt`", evidence)

    def test_log_window_close_is_separate_from_panel_close(self):
        # Round 3 (Codex P2): the log viewer is its own window.
        self.assertIn("| Close the selection panel | `logs-panel-close` |", self.text)
        row = [l for l in self.text.splitlines() if l.startswith("| Close the log window")][0]
        self.assertIn("Logs: <container>", row)
        self.assertIn("peekaboo window close", row)
        self.assertIn("close button", row)

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
