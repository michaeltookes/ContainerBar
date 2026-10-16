"""Zero-token hourly check for the ContainerBar QA lane (CB-105, story 6 AC1).

Runs from launchd com.genkeilabs.containerbar-hourly through
containerbar-hourly.sh, which takes the shared desktop lock first (exit 75
from the lock tool means a pass or another brief holds it: skip). No model,
no AppleScript, no GUI. Each external call has its own timeout; the lock
tool's 55 s timeout bounds the whole run.

Posts through the webhook named in ~/.openclaw/.env only when the set of
failing checks changes (failure, then recovery) or the stale-marker backstop
ran. Green runs post nothing. A post that fails leaves both the failure set
and the pending backstop events in the state file, so the next run posts them.

Budget: the checks and the backstop share one deadline (HOURLY_BUDGET_S from
the start); every probe's timeout is capped by it, and a check with no time
left is not run. That leaves POST_TIMEOUT_S for the webhook and time for the
state file and the log inside the wrapper's 55 s limit. A check that is not
observed this run (no time left, or the app check while CI is busy) keeps its
previous result instead of reading as a recovery.
"""
from __future__ import annotations

import json
import plistlib
import re
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime
from typing import Callable, Dict, List, Optional, Tuple

from lane_core import (APP_NAME, STALE_MARKER_S, Lane, baseline_diff, ci_busy, fixture_status,
                       marker_age, read_env_file, read_json, write_json)
from lane_restore import restore

try:
    from zoneinfo import ZoneInfo
except ImportError:  # Python 3.8 and older
    ZoneInfo = None  # type: ignore

RSS_LIMIT_KB = 200 * 1024
CPU_PER_HOUR_S = 36.0
WINDOW = (8, 20)  # 08:00-20:00 Central, inclusive of the 20:xx run
RELEASE_URL = "https://api.github.com/repos/michaeltookes/ContainerBar/releases/latest"
APPCAST_URL = "https://michaeltookes.github.io/ContainerBar/appcast.xml"
CASK_URL = "https://raw.githubusercontent.com/michaeltookes/homebrew-tap/main/Casks/containerbar.rb"
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
LOG_ROTATE_S = 7 * 24 * 3600
WRAPPER_LIMIT_S = 55   # containerbar-hourly.sh --timeout
HOURLY_BUDGET_S = 40   # checks + backstop
POST_TIMEOUT_S = 8     # webhook; the rest of the limit is state and log writes
FETCH_TIMEOUT_S = 8

Fetch = Callable[[str, float], Optional[str]]


def http_get(url: str, timeout: float = FETCH_TIMEOUT_S) -> Optional[str]:
    req = urllib.request.Request(url, headers={"User-Agent": "containerbar-qa-hourly"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.read().decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 - any network failure is "unreadable"
        return None


def appcast_version(xml_text: str) -> Optional[str]:
    """Top item's sparkle:shortVersionString (child element or enclosure attribute)."""
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return None
    item = root.find("./channel/item")
    if item is None:
        return None
    child = item.find("{%s}shortVersionString" % SPARKLE_NS)
    if child is not None and child.text:
        return child.text.strip()
    enclosure = item.find("enclosure")
    if enclosure is not None:
        return enclosure.get("{%s}shortVersionString" % SPARKLE_NS)
    return None


def cask_version(rb_text: str) -> Optional[str]:
    match = re.search(r'^\s*version\s+"([^"]+)"', rb_text, re.MULTILINE)
    return match.group(1) if match else None


def installed_version(app_path: str) -> Optional[str]:
    try:
        with open(app_path + "/Contents/Info.plist", "rb") as handle:
            return str(plistlib.load(handle).get("CFBundleShortVersionString"))
    except (OSError, ValueError, plistlib.InvalidFileException):
        return None


def _fetch_within(lane: Lane, fetch: Fetch, url: str, deadline: float) -> Optional[str]:
    remaining = deadline - lane.clock.now()
    if remaining <= 0:
        return None
    return fetch(url, min(FETCH_TIMEOUT_S, remaining))


def check_release(lane: Lane, fetch: Fetch, deadline: float) -> Tuple[Optional[str], str]:
    tag = None
    body = _fetch_within(lane, fetch, RELEASE_URL, deadline)
    if body:
        try:
            tag = str(json.loads(body).get("tag_name", "")).lstrip("v") or None
        except ValueError:
            tag = None
    appcast = _fetch_within(lane, fetch, APPCAST_URL, deadline)
    cask = _fetch_within(lane, fetch, CASK_URL, deadline)
    versions = {
        "tag": tag,
        "appcast": appcast_version(appcast) if appcast else None,
        "cask": cask_version(cask) if cask else None,
        "installed": installed_version(lane.app_path),
    }
    detail = " ".join("%s=%s" % (k, v or "?") for k, v in versions.items())
    if any(v is None for v in versions.values()):
        return "release-unreadable", detail
    if len(set(versions.values())) != 1:
        return "release-drift", detail
    return None, detail


def parse_cputime(text: str) -> float:
    """ps TIME: [[dd-]hh:]mm:ss[.cc] -> seconds."""
    days = 0
    if "-" in text:
        day_text, text = text.split("-", 1)
        days = int(day_text)
    seconds = 0.0
    for part in text.split(":"):
        seconds = seconds * 60 + float(part)
    return days * 86400 + seconds


def check_app(lane: Lane, state: Dict[str, object], deadline: float) -> Tuple[Optional[str], str]:
    rc, out = lane.call(["pgrep", "-x", APP_NAME], 5, deadline)
    if rc != 0 or not out.split():
        state.pop("cpu_sample", None)
        return "app-not-running", "pgrep found no process"
    pid = int(out.split()[0])
    rc, out = lane.call(["ps", "-o", "rss=,time=", "-p", str(pid)], 5, deadline)
    fields = out.split()
    if rc != 0 or len(fields) < 2:
        return "app-not-running", "ps could not read pid %d" % pid
    rss_kb, cpu = int(fields[0]), parse_cputime(fields[1])
    now = lane.clock.now()
    previous = state.get("cpu_sample") or {}
    state["cpu_sample"] = {"pid": pid, "cpu": cpu, "at": now}
    detail = "pid=%d rss=%dMB cpu=%.1fs" % (pid, rss_kb // 1024, cpu)
    if rss_kb >= RSS_LIMIT_KB:
        return "app-rss-high", detail
    if isinstance(previous, dict) and previous.get("pid") == pid:
        elapsed = max(now - float(previous["at"]), 1.0)
        used = cpu - float(previous["cpu"])
        budget = CPU_PER_HOUR_S * max(elapsed, 3600.0) / 3600.0
        detail += " cpu+%.1fs/%.0fmin" % (used, elapsed / 60)
        if used >= budget:
            return "app-cpu-high", detail
    return None, detail


def check_fixtures(lane: Lane, deadline: float) -> Tuple[Optional[str], str]:
    state, states = fixture_status(lane, deadline)
    if states is None:
        return "qa-runtime-down", "cbqa-ctl status %s" % state
    diffs = baseline_diff(states)
    if diffs:
        return "fixture-drift", "; ".join(diffs)
    return None, "baseline"


def check_gatekeeper(lane: Lane, deadline: float) -> Tuple[Optional[str], str]:
    rc, _ = lane.call(["spctl", "--assess", "--type", "execute", lane.app_path], 15, deadline)
    return (None, "accepted") if rc == 0 else ("gatekeeper-rejected", "spctl rc=%d" % rc)


def central_hour(now: float) -> int:
    if ZoneInfo is not None:
        return datetime.fromtimestamp(now, ZoneInfo("America/Chicago")).hour
    return datetime.fromtimestamp(now).hour


def webhook_url(lane: Lane) -> Optional[str]:
    key = lane.setting("CBQA_WEBHOOK_KEY", "CONTAINERBAR_QA_WEBHOOK")
    return read_env_file(lane.openclaw_env).get(key) or None


def post_webhook(url: str, text: str) -> bool:
    """POST one Discord message; bounded by POST_TIMEOUT_S."""
    data = json.dumps({"content": text[:1900]}).encode()
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json",
                                                          "User-Agent": "containerbar-qa-hourly"})
    try:
        with urllib.request.urlopen(req, timeout=POST_TIMEOUT_S):
            return True
    except Exception:  # noqa: BLE001
        return False


def append_log(lane: Lane, line: str) -> None:
    log = lane.artifacts / "hourly.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    stamp = lane.artifacts / "hourly.log.rotated"
    now = lane.clock.now()
    try:
        last = float(stamp.read_text())
    except (OSError, ValueError):
        last = now
        stamp.write_text(str(now))
    if now - last >= LOG_ROTATE_S and log.exists():
        log.replace(log.with_name("hourly.log.1"))
        stamp.write_text(str(now))
    stamp_text = datetime.fromtimestamp(now).strftime("%Y-%m-%dT%H:%M:%S%z")
    with open(str(log), "a") as handle:
        handle.write("%s %s\n" % (stamp_text, line))


def hourly(lane: Lane, fetch: Fetch = http_get,
           post: Callable[[str, str], bool] = post_webhook,
           force_window: bool = False) -> Dict[str, object]:
    """One hourly run. Returns a summary (also logged) for tests and the shell wrapper."""
    start = lane.clock.now()
    deadline = start + HOURLY_BUDGET_S
    hour = central_hour(start)
    if not force_window and not (WINDOW[0] <= hour <= WINDOW[1]):
        append_log(lane, "skipped outside-window")
        return {"result": "skipped", "failures": [], "events": [], "posted": None, "message": None}

    state_path = lane.artifacts / "hourly-state.json"
    state = read_json(state_path) or {}
    results = state.get("checks")
    results = dict(results) if isinstance(results, dict) else {}   # check -> failure or None
    infos = state.get("details")
    infos = dict(infos) if isinstance(infos, dict) else {}         # check -> detail of that result
    pending = [e for e in state.get("pending_events") or [] if isinstance(e, str)]
    details: List[str] = []

    age = marker_age(lane)
    if age is not None and age > STALE_MARKER_S:
        ok, notes = restore(lane, deadline=deadline)
        pending.append("restore-backstop-ran" if ok else "restore-backstop-failed")
        details.append("backstop: %s" % "; ".join(notes))
        results["backstop"] = None if ok else "restore-backstop-failed"
        infos["backstop"] = notes[-1] if notes else ""
    else:
        results["backstop"] = None

    busy, why = ci_busy(lane, deadline)
    details.append("ci=%s%s" % ("busy" if busy else "idle", " (%s)" % ", ".join(why) if why else ""))

    checks = [("release", lambda: check_release(lane, fetch, deadline)),
              ("app", lambda: check_app(lane, state, deadline)),
              ("fixtures", lambda: check_fixtures(lane, deadline)),
              ("gatekeeper", lambda: check_gatekeeper(lane, deadline))]
    for name, run_check in checks:
        if name == "app" and busy:
            details.append("app: not observed (ci-busy), keeping %s" % (results.get("app") or "ok"))
            state.pop("cpu_sample", None)
            continue
        if lane.clock.now() >= deadline:
            details.append("%s: not run (out of time), keeping %s" % (name, results.get(name) or "ok"))
            continue
        failure, detail = run_check()
        details.append("%s: %s" % (name, detail))
        results[name] = failure
        infos[name] = detail

    current = sorted({f for f in results.values() if f})
    failure_detail = {f: infos.get(n, "") for n, f in results.items() if f}
    previous = state.get("failing")
    previous = sorted(previous) if isinstance(previous, list) else []
    parts: List[str] = []
    if pending:
        parts.append(", ".join(pending))
    if current != previous and current:
        parts.append("FAIL %s | %s" % (", ".join(current),
                                       " | ".join("%s: %s" % (f, failure_detail[f]) for f in current)))
    elif current != previous:
        parts.append("recovered (was %s)" % ", ".join(previous))
    message = "ContainerBar hourly QA: %s" % " | ".join(parts) if parts else None

    posted = False
    if message:
        url = webhook_url(lane)
        posted = bool(url) and post(url, message)
        if not posted:
            details.append("post failed or no webhook configured; will retry next run")
    delivered = message is None or posted
    state["checks"] = results
    state["details"] = infos
    state["failing"] = current if delivered else previous
    state["pending_events"] = [] if delivered else pending
    write_json(state_path, state)
    result = "fail" if current else "ok"
    append_log(lane, "%s %s%s | %s" % (result, ",".join(current) or "-",
                                       " " + ",".join(pending) if pending else "", " | ".join(details)))
    return {"result": result, "failures": current, "events": pending,
            "posted": message if posted else None, "message": message,
            "elapsed": lane.clock.now() - start}
