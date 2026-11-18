"""CB-134: the Local Network grant probe (preflight 0g, architecture "Local Network grant rule").

The agent makes the one Test Connection attempt on `QA Runtime` (status item and panel through
CB-137's discovery, then Settings > Connections) and reports what it saw; this module decides.
It re-checks the shell, looks for a system dialog itself, classifies the outcome and, only for a
dialog-free Connected, appends `<YYYY-MM-DD> | <identity> | <ref> | lane` to the grant log (which
lives only in the workspace on the Mini). It clicks nothing and never writes an ask for a grant it
proves.

grant_probe() -> (exit code, lines). Exit 0 proven (gate open), 2 BLOCKED, 1 FAIL TC-CB-03, 64 usage.
"""
from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import List, Optional, Tuple

from lane_core import Lane, fixture_status, write_json

PROBE_BUDGET_S = 20.0
GRANT_LOG = "local-network-grants.log"
PROBE_FILE = "grant-probe.json"
DIALOG_BUDGET_S = 10.0
DIALOG_SHOT = "grant-dialog.png"
IDENTITIES = ("developer-id", "adhoc", "apple-development")
REF_PATTERNS = {"developer-id": r"-", "adhoc": r"\d+(?:\.\d+)*-\d+", "apple-development": r"[0-9A-Fa-f]{40}"}
NO_ROUTE = re.compile(r"no route to host|local network", re.I)
LOCAL_NETWORK_TEXT = re.compile(r"local network|find devices", re.I)
SYSTEM_PROMPT_PROCESSES = ("UserNotificationCenter", "CoreServicesUIAgent", "SecurityAgent")

# One line per window of every foreground process: process|window name|static texts joined by ;|x,y,w,h; a read failure is a `!ERR|process` line.
DIALOG_SCRIPT = """tell application "System Events"
 set out to ""
 repeat with p in (every process whose background only is false)
  try
   repeat with w in (every window of p)
    set t to ""
    try
     repeat with s in (every static text of w)
      set t to t & (value of s as text) & ";"
     end repeat
    on error
     set out to out & "!ERR|" & (name of p) & "||" & linefeed
    end try
    set b to ""
    try
     set b to ((item 1 of (position of w)) as integer as text) & "," & ((item 2 of (position of w)) as integer as text) & "," & ((item 1 of (size of w)) as integer as text) & "," & ((item 2 of (size of w)) as integer as text)
    end try
    set out to out & (name of p) & "|" & (name of w as text) & "|" & t & "|" & b & linefeed
   end repeat
  on error
   set out to out & "!ERR|" & (name of p) & "||" & linefeed
  end try
 end repeat
 return out
end tell"""


BOUNDS = re.compile(r"\d+,\d+,\d+,\d+")


def dialog_visible(lane: Lane) -> Tuple[Optional[str], str]:
    """(kind, bounds): kind is 'local-network' (ContainerBar's own dialog), 'system-prompt',
    'inspect-failed' (the AX inspection itself failed, so absence is unproven) or None.
    bounds is 'x,y,w,h' of the dialog window, or '' when unknown."""
    rc, out = lane.run(["osascript", "-e", DIALOG_SCRIPT], DIALOG_BUDGET_S)
    if rc != 0:
        return "inspect-failed", ""
    rows = []
    for line in out.splitlines():
        parts = line.split("|")
        proc = parts[0].strip()
        if proc == "!ERR":
            return "inspect-failed", ""  # a window list could not be read: absence is unproven
        texts = parts[2] if len(parts) > 2 else ""
        bounds = parts[3].strip() if len(parts) > 3 else ""
        rows.append((proc, texts, bounds if BOUNDS.fullmatch(bounds) else ""))

    def own_local_network(proc: str, texts: str) -> bool:
        # Only ContainerBar's own prompt: another app's "find devices" dialog is a system prompt.
        return bool(LOCAL_NETWORK_TEXT.search(texts)) and (
            proc == "ContainerBar" or (proc in SYSTEM_PROMPT_PROCESSES and "ContainerBar" in texts))

    # Any other system prompt wins over the Local Network exception (Stop and ask rule).
    for proc, texts, bounds in rows:
        if proc in SYSTEM_PROMPT_PROCESSES and not own_local_network(proc, texts):
            return "system-prompt", bounds
    for proc, texts, bounds in rows:
        if own_local_network(proc, texts):
            return "local-network", bounds
    return None, ""


def has_line(log: Path, identity: str, ref: str) -> bool:
    try:
        text = log.read_text()
    except OSError:
        return False
    for line in text.splitlines():
        parts = [p.strip() for p in line.split("|")]
        if len(parts) >= 3 and parts[1] == identity and parts[2] == ref:
            return True
    return False


def append_line(lane: Lane, identity: str, ref: str) -> bool:
    """Append the grant line unless an equal identity/ref line exists. True when written."""
    log = lane.state_dir / GRANT_LOG
    if has_line(log, identity, ref):
        return False
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(str(log), "a") as handle:
        handle.write("%s | %s | %s | lane\n" % (time.strftime("%Y-%m-%d", time.localtime(lane.clock.now())),
                                               identity, ref))
    return True


def _screenshot(lane: Lane, run_dir: Path, bounds: str) -> str:
    """Capture only the dialog window; with no known bounds keep no image (evidence rules)."""
    if not bounds:
        return "omitted (dialog bounds unknown; the full display is never kept)"
    shot = run_dir / "assets" / "TC-CB-03" / DIALOG_SHOT
    shot.parent.mkdir(parents=True, exist_ok=True)
    rc, _ = lane.run(["screencapture", "-x", "-R", bounds, str(shot)], 10)
    return str(shot) if rc == 0 else "screenshot failed"


def _first_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()[:200]
    return ""


def grant_probe(lane: Lane, run_dir: Path, identity: str, ref: str, result: str,
                error_text: str = "", elapsed: float = 0.0) -> Tuple[int, List[str]]:
    """result: connected | failed | timeout, as the agent saw Test Connection end."""
    if identity not in IDENTITIES or not re.fullmatch(REF_PATTERNS[identity], ref):
        return 64, ["usage: identity is developer-id (ref -), adhoc (ref <version>-<build>) "
                    "or apple-development (ref the identity SHA-1)"]
    if result not in ("connected", "failed", "timeout"):
        return 64, ["usage: result is connected, failed or timeout"]
    marker = run_dir / PROBE_FILE
    if marker.exists():
        return 1, ["grant probe already ran in this run folder (one attempt per pass); no second attempt"]
    state, _ = fixture_status(lane)
    if state != "ok":
        return 2, ["BLOCKED qa-runtime-down: the shell ssh cbqa-ctl status failed; no probe, no grant line"]
    run_dir.mkdir(parents=True, exist_ok=True)
    record = {"identity": identity, "ref": ref, "result": result}
    dialog, bounds = dialog_visible(lane)
    if dialog == "inspect-failed":
        write_json(marker, dict(record, verdict="inspect-failed"))
        return 2, ["BLOCKED dialog-inspection-failed: osascript could not list windows (timeout or Accessibility "
                   "permission missing), so a system dialog cannot be ruled out; no grant line, gate stays closed",
                   "ASK owner: allow Accessibility for the lane's osascript host in System Settings > Privacy & Security, "
                   "then the next pass probes again"]
    if dialog == "system-prompt":
        write_json(marker, dict(record, verdict="system-prompt"))
        return 2, ["BLOCKED system-prompt: a system dialog is on screen during the probe; nothing clicked, "
                   "no grant line (CB-116 rule for other prompts)",
                   "screenshot: %s" % _screenshot(lane, run_dir, bounds),
                   "ASK owner: answer the system dialog over the remote desktop, then the next pass proves the grant"]
    if dialog == "local-network":
        write_json(marker, dict(record, verdict="dialog"))
        return 2, ["BLOCKED local-network-denied: the Local Network dialog is on screen; nothing clicked, no grant line",
                   "screenshot: %s" % _screenshot(lane, run_dir, bounds),
                   "ASK owner: click Allow on the ContainerBar Local Network dialog over the remote desktop; "
                   "the next pass's probe proves the grant and writes the line"]
    if result == "connected" and elapsed <= PROBE_BUDGET_S:
        written = append_line(lane, identity, ref)
        write_json(marker, dict(record, verdict="proven", written=written))
        return 0, ["grant: proven by probe", "gate: open (%s line %s)" % (identity, "written" if written else "already present")]
    if result == "failed" and NO_ROUTE.search(error_text):
        write_json(marker, dict(record, verdict="denied"))
        return 2, ["BLOCKED local-network-denied: Test Connection failed (%s) with no dialog while the shell works; no grant line"
                   % _first_line(error_text),
                   "ASK owner: turn ContainerBar on in System Settings > Privacy & Security > Local Network; "
                   "the next pass's probe proves the grant and writes the line"]
    write_json(marker, dict(record, verdict="cannot-connect"))
    why = "timeout after %ds" % PROBE_BUDGET_S if result in ("timeout", "connected") else _first_line(error_text)
    return 1, ["FAIL TC-CB-03: Test Connection did not connect (%s); no grant line" % why,
               "SSH-dependent cases: blocked app-cannot-connect"]
