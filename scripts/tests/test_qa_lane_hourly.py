#!/usr/bin/env python3
"""CB-105 story 6 AC1: the zero-token hourly check and its launchd entry point."""
from __future__ import annotations

import json
import os
import plistlib
import subprocess
import sys
import unittest
from pathlib import Path

from qa_lane_fakes import LANE_DIR, FakeClock, FakeRunner, make_lane, status_json

import lane_core
import lane_hourly
from lane_hourly import appcast_version, cask_version, hourly, parse_cputime

APPCAST = """<?xml version="1.0"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>
<item><title>2.0.5</title><sparkle:shortVersionString>{v}</sparkle:shortVersionString></item>
<item><title>old</title><sparkle:shortVersionString>1.0.0</sparkle:shortVersionString></item>
</channel></rss>"""


START_10AM_CENTRAL = 1800028800.0  # 2027-01-15 10:00 America/Chicago


class Env:
    """A healthy Mini: versions agree, app idle, fixtures at baseline, Gatekeeper accepts."""

    def __init__(self, test, hour_ok=True):
        self.runner = FakeRunner()
        self.runner.app_pid = 4100
        self.rss_kb, self.cpu = 80 * 1024, "0:10.00"
        self.runner.on("ps -o rss=,time=", lambda argv: (0, "%d %s\n" % (self.rss_kb, self.cpu)))
        self.spctl_rc = 0
        self.runner.on("spctl", lambda argv: (self.spctl_rc, ""))
        self.clock = FakeClock(START_10AM_CENTRAL)
        if not hour_ok:
            self.clock.t += 13 * 3600  # 23:00 Central
        self.lane, self.root = make_lane(test, self.runner, self.clock)
        self.lane.openclaw_env.write_text("CONTAINERBAR_QA_WEBHOOK=https://example.invalid/hook\n")
        app = Path(self.lane.app_path, "Contents")
        app.mkdir(parents=True)
        self.installed = "2.0.5"
        self.write_installed()
        self.versions = {"tag": "v2.0.5", "appcast": "2.0.5", "cask": "2.0.5"}
        self.posts = []
        self.fetch_timeouts = []
        self.fetch_cost = 0

    def write_installed(self):
        path = Path(self.lane.app_path, "Contents", "Info.plist")
        path.write_bytes(plistlib.dumps({"CFBundleShortVersionString": self.installed}))

    def fetch(self, url, timeout=8):
        self.fetch_timeouts.append(timeout)
        cost = self.fetch_cost
        if cost:
            self.clock.sleep(min(cost, timeout))
            if cost > timeout:
                return None
        if "releases/latest" in url:
            return json.dumps({"tag_name": self.versions["tag"]})
        if "appcast" in url:
            return APPCAST.format(v=self.versions["appcast"])
        if "homebrew-tap" in url:
            return 'cask "containerbar" do\n  version "%s"\nend\n' % self.versions["cask"]
        return None

    def post(self, url, text):
        self.posts.append(text)
        return True

    def run(self):
        return hourly(self.lane, fetch=self.fetch, post=self.post)


class HourlyTests(unittest.TestCase):
    def test_green_run_posts_nothing_and_logs(self):
        env = Env(self)
        result = env.run()
        self.assertEqual(result["result"], "ok")
        self.assertEqual(env.posts, [])
        log = (env.lane.artifacts / "hourly.log").read_text()
        self.assertIn(" ok - ", log)

    def test_outside_window_skips(self):
        env = Env(self, hour_ok=False)
        self.assertEqual(env.run()["result"], "skipped")
        self.assertEqual(env.runner.calls, [])

    def test_release_drift_posts_once_then_recovery_posts_once(self):
        env = Env(self)
        env.versions["cask"] = "2.0.4"
        self.assertEqual(env.run()["failures"], ["release-drift"])
        self.assertEqual(len(env.posts), 1)
        self.assertIn("FAIL release-drift", env.posts[0])
        self.assertIn("cask=2.0.4", env.posts[0])
        env.run()
        self.assertEqual(len(env.posts), 1)  # unchanged state: no second post
        env.versions["cask"] = "2.0.5"
        env.run()
        self.assertEqual(len(env.posts), 2)
        self.assertIn("recovered", env.posts[1])

    def test_unreadable_appcast_is_a_failure(self):
        env = Env(self)
        original = env.fetch
        env.fetch = lambda url, timeout: None if "appcast" in url else original(url, timeout)
        self.assertEqual(env.run()["failures"], ["release-unreadable"])

    def test_app_not_running(self):
        env = Env(self)
        env.runner.app_pid = None
        self.assertIn("app-not-running", env.run()["failures"])

    def test_rss_over_200_mb(self):
        env = Env(self)
        env.rss_kb = 201 * 1024
        self.assertIn("app-rss-high", env.run()["failures"])

    def test_cpu_budget_36_seconds_per_hour(self):
        env = Env(self)
        env.run()                      # first sample: cpu 10 s
        env.clock.t += 3600
        env.cpu = "0:45.00"            # +35 s in the hour: within budget
        self.assertEqual(env.run()["failures"], [])
        env.clock.t += 3600
        env.cpu = "1:22.00"            # +37 s in the hour: over budget
        self.assertEqual(env.run()["failures"], ["app-cpu-high"])

    def test_new_pid_resets_cpu_baseline(self):
        env = Env(self)
        env.run()
        env.runner.app_pid = 4200
        env.cpu = "9:00.00"
        env.clock.t += 3600
        self.assertEqual(env.run()["failures"], [])

    def test_ci_busy_skips_app_check_but_runs_the_rest(self):
        env = Env(self)
        env.runner.worker = True
        env.runner.app_pid = None
        env.versions["tag"] = "v9.9.9"
        result = env.run()
        self.assertEqual(result["failures"], ["release-drift"])
        self.assertFalse(env.runner.ran("pgrep", "ContainerBar"))
        self.assertTrue(env.runner.ran("spctl"))
        self.assertIn("ci=busy", (env.lane.artifacts / "hourly.log").read_text())

    def test_exited_target_is_fixture_drift(self):
        env = Env(self)
        env.runner.status = [status_json({"cbqa-target": "exited"})]
        self.assertEqual(env.run()["failures"], ["fixture-drift"])

    def test_unreachable_runtime(self):
        env = Env(self)
        env.runner.status = [None]
        self.assertEqual(env.run()["failures"], ["qa-runtime-down"])

    def test_gatekeeper_rejection(self):
        env = Env(self)
        env.spctl_rc = 3
        self.assertEqual(env.run()["failures"], ["gatekeeper-rejected"])

    def test_stale_marker_runs_backstop_and_reports_it(self):
        env = Env(self)
        lane_core.write_json(env.lane.marker, {"t0": env.clock.now() - 32 * 60})
        env.runner.status = [status_json({"cbqa-target": "exited"}), status_json()]
        result = env.run()
        self.assertEqual(result["events"], ["restore-backstop-ran"])
        self.assertEqual(result["failures"], [])
        self.assertFalse(env.lane.marker.exists())
        self.assertTrue(env.runner.ran("cbqa-ctl", "api-start"))
        self.assertTrue(env.runner.ran("cbqa-ctl", "reset"))
        self.assertEqual(len(env.posts), 1)
        self.assertIn("restore-backstop-ran", env.posts[0])
        self.assertFalse(env.runner.ran("osascript"))

    def test_young_marker_is_left_alone(self):
        env = Env(self)
        lane_core.write_json(env.lane.marker, {"t0": env.clock.now() - 10 * 60})
        result = env.run()
        self.assertEqual(result["events"], [])
        self.assertTrue(env.lane.marker.exists())

    def test_failed_post_retries_next_run(self):
        env = Env(self)
        env.versions["cask"] = "2.0.4"
        env.post = lambda url, text: env.posts.append(text) and False
        env.run()
        env.run()
        self.assertEqual(len(env.posts), 2)

    def test_no_applescript_or_gui_calls(self):
        env = Env(self)
        lane_core.write_json(env.lane.marker, {"t0": env.clock.now() - 40 * 60})
        env.run()
        for call in env.runner.calls:
            self.assertNotIn(call[0], ("osascript", "open", "peekaboo"))


class CodexRoundOneTests(unittest.TestCase):
    """PR 76 Codex round 1, items 1-3."""

    def test_stalled_services_stay_inside_the_wrapper_limit_and_still_post(self):
        env = Env(self)
        env.versions["cask"] = "2.0.4"          # a failure to report
        env.fetch_cost = 30                      # every HTTP call hangs to its timeout
        env.runner.costs = [("gh api", 60), ("ssh", 60), ("spctl", 60), ("pgrep -x Runner", 60)]
        result = env.run()
        self.assertLessEqual(result["elapsed"], lane_hourly.HOURLY_BUDGET_S)
        self.assertLess(lane_hourly.HOURLY_BUDGET_S + lane_hourly.POST_TIMEOUT_S,
                        lane_hourly.WRAPPER_LIMIT_S - 5)
        self.assertTrue((env.lane.artifacts / "hourly-state.json").exists())
        self.assertIsNotNone(result["message"])
        self.assertEqual(len(env.posts), 1)
        self.assertTrue(all(t <= lane_hourly.FETCH_TIMEOUT_S for t in env.fetch_timeouts))

    def test_backstop_restore_shares_the_budget(self):
        env = Env(self)
        lane_core.write_json(env.lane.marker, {"t0": env.clock.now() - 40 * 60})
        env.runner.status = [status_json({"cbqa-target": "exited"})]
        env.runner.costs = [("ssh -o ConnectTimeout=5 -o BatchMode=yes cbqa-ctl reset", 200)]
        result = env.run()
        self.assertLessEqual(result["elapsed"], lane_hourly.HOURLY_BUDGET_S)
        self.assertIn("restore-backstop-failed", result["failures"])
        self.assertTrue(env.lane.marker.exists())   # kept for the next run
        self.assertEqual(len(env.posts), 1)

    def test_app_failure_survives_a_ci_busy_run(self):
        env = Env(self)
        env.runner.app_pid = None
        env.run()
        self.assertIn("FAIL app-not-running", env.posts[-1])
        env.runner.worker = True                 # CI busy: the app cannot be observed
        env.clock.t += 3600
        result = env.run()
        self.assertEqual(result["failures"], ["app-not-running"])
        self.assertEqual(len(env.posts), 1)      # no false "recovered"
        env.runner.worker = False
        env.runner.app_pid = 4300
        env.clock.t += 3600
        self.assertEqual(env.run()["failures"], [])
        self.assertIn("recovered", env.posts[-1])

    def test_unobserved_check_out_of_time_keeps_its_previous_result(self):
        env = Env(self)
        env.spctl_rc = 3
        env.run()
        env.spctl_rc = 0
        env.clock.t += 3600
        env.fetch_cost = 8                        # three fetches eat 24 s
        env.runner.costs = [("ssh", 20)]          # the fixture check eats the rest
        result = env.run()
        self.assertTrue(any("gatekeeper: not run (out of time)" in line
                            for line in (env.lane.artifacts / "hourly.log").read_text().splitlines()))
        self.assertIn("gatekeeper-rejected", result["failures"])

    def test_backstop_event_is_retried_until_delivered(self):
        env = Env(self)
        lane_core.write_json(env.lane.marker, {"t0": env.clock.now() - 40 * 60})
        attempts = []
        env.post = lambda url, text: attempts.append(text) and False
        env.run()
        self.assertFalse(env.lane.marker.exists())
        env.clock.t += 3600
        env.post = lambda url, text: attempts.append(text) or True
        env.run()
        self.assertEqual(len(attempts), 2)
        self.assertIn("restore-backstop-ran", attempts[1])
        env.clock.t += 3600
        env.run()
        self.assertEqual(len(attempts), 2)       # delivered once, then cleared


class ParsingTests(unittest.TestCase):
    def test_appcast_child_and_enclosure_forms(self):
        self.assertEqual(appcast_version(APPCAST.format(v="2.0.5")), "2.0.5")
        enclosure = ('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
                     '<enclosure url="x" sparkle:shortVersionString="2.1.0"/></item></channel></rss>')
        self.assertEqual(appcast_version(enclosure), "2.1.0")
        self.assertIsNone(appcast_version("not xml"))

    def test_cask_version(self):
        self.assertEqual(cask_version('cask "x" do\n  version "2.0.4"\n'), "2.0.4")

    def test_cputime_formats(self):
        self.assertEqual(parse_cputime("0:10.50"), 10.5)
        self.assertEqual(parse_cputime("1:02:03"), 3723)
        self.assertEqual(parse_cputime("1-00:00:01"), 86401)


class LaunchdEntryPointTests(unittest.TestCase):
    """containerbar-hourly.sh under a stand-in for the shared lock tool."""

    def run_script(self, lock_rc):
        lane, root = make_lane(self)
        tool = root / "device_lock.py"
        tool.write_text("import sys\nsys.exit(%d)\n" % lock_rc)
        env = dict(os.environ, HOME=str(root / "home"), CBQA_WORKSPACE=str(lane.workspace),
                   CBQA_LOCK_TOOL=str(tool), CBQA_PYTHON=sys.executable)
        done = subprocess.run(["/bin/zsh", os.path.join(LANE_DIR, "containerbar-hourly.sh")],
                              env=env, capture_output=True, text=True, timeout=60)
        log = lane.artifacts / "hourly.log"
        return done.returncode, log.read_text() if log.exists() else ""

    @unittest.skipUnless(os.path.exists("/bin/zsh"), "needs zsh")
    def test_lock_held_skips_the_run(self):
        rc, log = self.run_script(75)
        self.assertEqual(rc, 0)
        self.assertIn("skipped desktop-busy", log)

    @unittest.skipUnless(os.path.exists("/bin/zsh"), "needs zsh")
    def test_timeout_is_logged(self):
        rc, log = self.run_script(124)
        self.assertEqual(rc, 0)
        self.assertIn("timeout after 55s", log)

    def test_plist_template_renders_valid_hourly_schedule(self):
        lane, root = make_lane(self)
        if not os.path.exists("/usr/bin/plutil"):
            self.skipTest("needs macOS plutil")
        env = dict(os.environ, HOME=str(root / "home"), CBQA_WORKSPACE=str(lane.workspace))
        done = subprocess.run(["/bin/zsh", os.path.join(LANE_DIR, "install.sh")], env=env,
                              capture_output=True, text=True, timeout=60)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertIn("dry-run:", done.stdout)
        self.assertFalse(Path(root, "home", "Library", "LaunchAgents").exists())
        out = root / "rendered.plist"
        done = subprocess.run(["/bin/zsh", os.path.join(LANE_DIR, "install.sh"), "--render", str(out)],
                              env=env, capture_output=True, text=True, timeout=60)
        self.assertEqual(done.returncode, 0, done.stderr)
        agent = plistlib.loads(out.read_bytes())
        self.assertEqual(agent["Label"], "com.genkeilabs.containerbar-hourly")
        self.assertEqual([i["Hour"] for i in agent["StartCalendarInterval"]], list(range(8, 21)))
        self.assertTrue(agent["ProgramArguments"][1].endswith("tools/containerbar-qa/containerbar-hourly.sh"))
        # Codex round 1 item 4: launchd carries the workspace the installer targeted.
        self.assertEqual(agent["EnvironmentVariables"]["CBQA_WORKSPACE"], str(lane.workspace))


if __name__ == "__main__":
    unittest.main()
