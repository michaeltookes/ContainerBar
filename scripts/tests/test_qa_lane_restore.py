#!/usr/bin/env python3
"""CB-105 story 6 AC4 and AC6: the no-GUI restore, the forwarded socket, preference drift."""
from __future__ import annotations

import os
import plistlib
import re
import socket
import unittest
from pathlib import Path

from qa_lane_fakes import LANE_DIR, FakeRunner, make_lane, status_json

import lane_core
from lane_prefs import drift
from lane_restore import restore, start_forward, stop_forward

FORWARD_CMD = "ssh -nNT -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes -L {sock}:/run/cbqa-api/podman.sock cbqa-tunnel"


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.runner = FakeRunner()
        self.lane, self.root = make_lane(self, self.runner)
        self.signalled = []

    def terminate(self, pid):
        self.signalled.append(pid)
        self.runner.processes.pop(pid, None)

    def record_forward(self, pid, command):
        self.lane.socket.parent.mkdir(parents=True, exist_ok=True)
        self.lane.socket.write_text("")
        self.runner.processes[pid] = command
        lane_core.write_json(self.lane.forward_file, {"pid": pid, "socket": str(self.lane.socket)})

    def test_baseline_restore_runs_api_start_skips_reset_and_deletes_marker(self):
        lane_core.write_json(self.lane.marker, {"t0": 1})
        ok, notes = restore(self.lane, terminate=self.terminate)
        self.assertTrue(ok)
        self.assertTrue(self.runner.ran("cbqa-ctl", "api-start"))
        self.assertFalse(self.runner.ran("cbqa-ctl", "reset"))
        self.assertFalse(self.lane.marker.exists())
        self.assertIn("run marker deleted", notes)

    def test_target_exited_triggers_reset_and_verifies_baseline(self):
        self.runner.status = [status_json({"cbqa-target": "exited"}), status_json()]
        ok, notes = restore(self.lane, terminate=self.terminate)
        self.assertTrue(ok)
        self.assertTrue(self.runner.ran("cbqa-ctl", "reset"))
        self.assertIn("fixtures at baseline after reset", notes)

    def test_extra_container_is_not_baseline(self):
        self.runner.status = [status_json(extra=["intruder"]), status_json()]
        ok, _ = restore(self.lane, terminate=self.terminate)
        self.assertTrue(ok)
        self.assertTrue(self.runner.ran("cbqa-ctl", "reset"))

    def test_failed_reset_keeps_marker_and_fails(self):
        lane_core.write_json(self.lane.marker, {"t0": 1})
        self.runner.status = [status_json({"cbqa-target": "exited"})]
        ok, notes = restore(self.lane, terminate=self.terminate)
        self.assertFalse(ok)
        self.assertTrue(self.lane.marker.exists())
        self.assertIn("run marker kept: restore failed", notes)

    def test_keep_marker_flag(self):
        lane_core.write_json(self.lane.marker, {"t0": 1})
        ok, _ = restore(self.lane, keep_marker=True, terminate=self.terminate)
        self.assertTrue(ok)
        self.assertTrue(self.lane.marker.exists())

    def test_recorded_forward_is_stopped_by_pid_and_socket_removed(self):
        self.record_forward(9100, FORWARD_CMD.format(sock=self.lane.socket))
        ok, notes = restore(self.lane, terminate=self.terminate)
        self.assertTrue(ok)
        self.assertEqual(self.signalled, [9100])
        self.assertFalse(self.lane.socket.exists())
        self.assertFalse(self.lane.forward_file.exists())

    def test_reused_pid_is_never_signalled(self):
        self.record_forward(9100, "/usr/sbin/someone-else --flag")
        stop_forward(self.lane, [], terminate=self.terminate)
        self.assertEqual(self.signalled, [])
        self.assertFalse(self.lane.socket.exists())

    def test_runtime_down_fails(self):
        self.runner.status = [None]
        ok, _ = restore(self.lane, terminate=self.terminate)
        self.assertFalse(ok)

    def test_only_qa_hosts_are_targeted(self):
        restore(self.lane, terminate=self.terminate)
        for call in self.runner.calls:
            if call[0] == "ssh":
                self.assertIn(call[-2], ("cbqa-ctl",))


class ForwardTests(unittest.TestCase):
    def setUp(self):
        self.runner = FakeRunner()
        self.lane, self.root = make_lane(self, self.runner)
        self.lane.socket = Path("/tmp/cbqa-test-%d.sock" % os.getpid())
        self.addCleanup(lambda: self.lane.socket.exists() and self.lane.socket.unlink())
        self.signalled = []
        self.sockets = []

    def terminate(self, pid):
        self.signalled.append(pid)
        self.runner.processes.pop(pid, None)

    def spawn_with_socket(self, argv):
        self.argv = argv
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(str(self.lane.socket))
        self.sockets.append(sock)
        self.addCleanup(sock.close)
        self.runner.processes[9200] = " ".join(argv)
        return 9200

    def spawn_without_socket(self, argv):
        self.runner.processes[9300] = " ".join(argv)
        return 9300

    def test_forward_ready_when_socket_appears(self):
        ok, notes = start_forward(self.lane, spawn=self.spawn_with_socket, terminate=self.terminate)
        self.assertTrue(ok, notes)
        self.assertIn("StreamLocalBindUnlink=yes", self.argv)
        self.assertEqual(self.argv[-1], "cbqa-tunnel")
        self.assertEqual(lane_core.read_json(self.lane.forward_file)["pid"], 9200)

    def test_forward_failed_after_ten_seconds_and_stopped(self):
        ok, notes = start_forward(self.lane, spawn=self.spawn_without_socket, terminate=self.terminate)
        self.assertFalse(ok)
        self.assertIn("forward-failed", notes[-2] + notes[-1] + " ".join(notes))
        self.assertEqual(self.signalled, [9300])
        self.assertLessEqual(self.lane.clock.elapsed(), 10.5)

    def test_leftover_forward_stopped_and_stale_socket_removed_first(self):
        self.lane.socket.write_text("stale")
        self.runner.processes[9100] = FORWARD_CMD.format(sock=self.lane.socket)
        lane_core.write_json(self.lane.forward_file, {"pid": 9100, "socket": str(self.lane.socket)})
        ok, _ = start_forward(self.lane, spawn=self.spawn_with_socket, terminate=self.terminate)
        self.assertTrue(ok)
        self.assertEqual(self.signalled, [9100])


class CodexRoundTwoTests(unittest.TestCase):
    """PR 76 Codex round 2, items 1-5 (restore, forward, preferences)."""

    def setUp(self):
        self.runner = FakeRunner()
        self.lane, self.root = make_lane(self, self.runner)
        self.signalled = []

    def terminate(self, pid):
        self.signalled.append(pid)
        self.runner.processes.pop(pid, None)

    def stubborn(self, pid):
        self.signalled.append(pid)       # the process ignores the signal

    def record_forward(self, pid, command, sock=None):
        sock = str(sock or self.lane.socket)
        self.runner.processes[pid] = command
        lane_core.write_json(self.lane.forward_file, {"pid": pid, "socket": sock})

    def test_backstop_restore_leaves_gui_cleanup_pending(self):
        lane_core.write_json(self.lane.marker, {"t0": 1})
        ok, notes = restore(self.lane, terminate=self.terminate, backstop=True)
        self.assertTrue(ok)
        self.assertFalse(self.lane.marker.exists())
        self.assertTrue(self.lane.gui_flag.exists())
        self.assertIn("gui-cleanup-pending recorded for the next pass", notes)

    def test_pass_restore_does_not_flag_gui_cleanup(self):
        lane_core.write_json(self.lane.marker, {"t0": 1})
        restore(self.lane, terminate=self.terminate)
        self.assertFalse(self.lane.gui_flag.exists())

    def test_stop_forward_respects_the_deadline_and_keeps_the_record(self):
        self.record_forward(9100, FORWARD_CMD.format(sock=self.lane.socket))
        self.runner.costs = [("ps -o command=", 4)]
        deadline = self.lane.clock.now() + 3
        notes = []
        self.assertFalse(stop_forward(self.lane, notes, self.terminate, deadline))
        self.assertLessEqual(self.lane.clock.now(), deadline)
        self.assertEqual(self.signalled, [])
        self.assertEqual(lane_core.read_json(self.lane.forward_file)["pid"], 9100)

    def test_restore_with_spent_budget_keeps_forward_and_marker(self):
        lane_core.write_json(self.lane.marker, {"t0": 1})
        self.record_forward(9100, FORWARD_CMD.format(sock=self.lane.socket))
        self.runner.costs = [("ssh", 21)]
        deadline = self.lane.clock.now() + 40
        ok, _ = restore(self.lane, terminate=self.terminate, deadline=deadline, backstop=True)
        self.assertFalse(ok)
        self.assertLessEqual(self.lane.clock.now(), deadline)
        self.assertTrue(self.lane.marker.exists())
        self.assertTrue(self.lane.forward_file.exists())
        self.assertFalse(self.lane.gui_flag.exists())

    def test_stubborn_forward_waits_are_capped(self):
        self.record_forward(9100, FORWARD_CMD.format(sock=self.lane.socket))
        deadline = self.lane.clock.now() + 2
        self.assertFalse(stop_forward(self.lane, [], self.stubborn, deadline))
        self.assertLessEqual(self.lane.clock.now(), deadline)

    def test_live_leftover_forward_blocks_a_new_tunnel(self):
        self.record_forward(9100, FORWARD_CMD.format(sock=self.lane.socket))
        spawned = []
        ok, notes = start_forward(self.lane, spawn=lambda argv: spawned.append(argv) or 9999,
                                  terminate=self.stubborn)
        self.assertFalse(ok)
        self.assertEqual(spawned, [])
        self.assertEqual(lane_core.read_json(self.lane.forward_file)["pid"], 9100)
        self.assertTrue(any("forward-failed" in n for n in notes))

    def test_only_the_exact_forward_argv_is_signalled(self):
        sock = str(self.lane.socket)
        lookalikes = [
            "ssh -nNT -L %s:/run/cbqa-api/podman.sock somewhere-else" % sock,
            "ssh -v -nNT -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes -L %s:/run/cbqa-api/podman.sock cbqa-tunnel" % sock,
            "ssh cbqa-ctl status %s /run/cbqa-api/podman.sock" % sock,
            "/usr/bin/vim %s /run/cbqa-api/podman.sock" % sock,
        ]
        for command in lookalikes:
            self.signalled = []
            self.record_forward(9100, command)
            stop_forward(self.lane, [], self.terminate)
            self.assertEqual(self.signalled, [], command)
        self.record_forward(9100, "/usr/bin/" + FORWARD_CMD.format(sock=sock))
        stop_forward(self.lane, [], self.terminate)
        self.assertEqual(self.signalled, [9100])

    def test_allowlist_includes_sparkle_and_login_keys(self):
        self.assertEqual(drift({"SUSkippedVersion": "2.0.5"}, {}), ["SUSkippedVersion"])
        self.assertEqual(drift({"SUHasLaunchedBefore": False}, {"SUHasLaunchedBefore": True}),
                         ["SUHasLaunchedBefore"])
        self.assertEqual(drift({"launchAtLogin": True}, {}), ["launchAtLogin"])
        self.assertEqual(drift({"launchAtLogin": False, "SUHasLaunchedBefore": True},
                               {"SUHasLaunchedBefore": True}), [])


class PrefsDriftTests(unittest.TestCase):
    HOSTS_A = b'[{"id":"A","name":"QA Runtime","sshUser":"cbqa-fwd","port":22}]'
    HOSTS_B = b'[{"port":22,"sshUser":"cbqa-fwd","name":"QA Runtime","id":"A"}]'

    def test_missing_refresh_interval_equals_default(self):
        self.assertEqual(drift({"refreshInterval": "10s"}, {}), [])

    def test_changed_refresh_interval_is_drift(self):
        self.assertEqual(drift({"refreshInterval": "30s"}, {}), ["refreshInterval"])

    def test_json_key_order_is_not_drift(self):
        self.assertEqual(drift({"dockerHosts": self.HOSTS_A}, {"dockerHosts": self.HOSTS_B}), [])

    def test_changed_host_field_is_drift(self):
        other = self.HOSTS_B.replace(b"cbqa-fwd", b"root")
        self.assertEqual(drift({"dockerHosts": self.HOSTS_A}, {"dockerHosts": other}), ["dockerHosts"])

    def test_plist_round_trip(self):
        from lane_prefs import drift_files
        lane, root = make_lane(self)
        before, base = root / "before.plist", root / "base.plist"
        before.write_bytes(plistlib.dumps({"showStoppedContainers": False}))
        base.write_bytes(plistlib.dumps({"showStoppedContainers": True}))
        self.assertEqual(drift_files(str(before), str(base)), ["showStoppedContainers"])


class NoSignalsByNameTests(unittest.TestCase):
    """Story 6 AC6: nothing in the lane stops a process by name or pattern."""

    def test_sources_never_use_pkill_killall_or_kill_by_name(self):
        for name in sorted(n for n in os.listdir(LANE_DIR) if n.endswith((".py", ".sh"))):
            text = Path(LANE_DIR, name).read_text()
            code = "\n".join(l for l in text.splitlines() if not l.lstrip().startswith("#"))
            self.assertNotRegex(code, r"\bpkill\b|\bkillall\b", name)
            self.assertNotRegex(code, r"(?m)^\s*kill\s", name)
            for call in re.findall(r"os\.kill\(([^)]*)\)", code):
                self.assertTrue(call.startswith("pid"), "%s: os.kill(%s)" % (name, call))

    def test_app_quit_goes_through_osascript_quit(self):
        text = Path(LANE_DIR, "lane_preflight.py").read_text()
        self.assertIn("'quit app \"%s\"'", text)


if __name__ == "__main__":
    unittest.main()
