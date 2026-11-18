#!/usr/bin/env python3
"""ContainerBar QA lane command line (CB-105). See README.md in this folder.

  preflight --session ID     step 0: CI wait, desktop lock, marker recovery
  normalise --token T        retry the quit/relaunch after closing dialogs
  case-gate --token T [TC-ID] before each case: lock ownership, time budget, CI; no wait
  restore [--keep-marker]    the no-GUI restore (containerbar-qa-restore.sh)
  gui-done                   step 5: the GUI restore succeeded, clear gui-cleanup-pending
  release --token T          release the desktop lock held for this pass (T: the
                             "lock token" run note); refuses another pass's lock
  forward-start              Unix-socket leg: start the SSH-forwarded socket
  forward-stop               stop that forward by its recorded PID
  prefs-drift BEFORE BASE    step 0e: which baseline preferences drifted
  ci-busy                    print busy/idle and the predicate's notes
  hourly-checks              the launchd hourly check (run under the lock)
  hourly-log TEXT            append one line to hourly.log
  find-status-item --run-dir D   CB-137: find the released app's status item (peekaboo or ax)
  open-panel --run-dir D [--shot F]   find, open and capture the panel (02-panel-open.png)
  close-panel                Escape the open status menu
  capture-status-item --run-dir D --case-dir C   CB-138: 01-status-item.png strip and the AX value
  hunt-checks --case-dir C --fixture-text absent|present   CB-138: the three hunt lines, recorded verbatim
  tc-cb-02-verdict --run-dir D --case-dir C   CB-138: PASS, FAIL P1 or BLOCKED evidence-incomplete <item>
  grant-probe --run-dir D --identity I --ref R --result connected|failed|timeout
                             CB-134: classify the one Test Connection attempt, write the grant line
  hold --run ID              internal: the lock holder's child process
Exit codes: 0 ok/ready, 1 failure, 2 blocked, 3 needs-normalise.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from lane_core import Lane, case_gate, ci_busy
from lane_discovery import close_panel, find_status_item, open_panel
from lane_evidence import capture_status_item, hunt_checks, verdict
from lane_grant import grant_probe
from lane_hourly import append_log, hourly
from lane_preflight import hold, normalise_after_dialogs, preflight, print_result, release_lock
from lane_prefs import drift_files
from lane_restore import gui_done, restore, start_forward, stop_forward


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    pre = sub.add_parser("preflight")
    pre.add_argument("--session", required=True)
    norm = sub.add_parser("normalise")
    norm.add_argument("--token", required=True)
    gate = sub.add_parser("case-gate")
    gate.add_argument("case", nargs="?", default="")
    gate.add_argument("--token", required=True)
    rest = sub.add_parser("restore")
    rest.add_argument("--keep-marker", action="store_true")
    sub.add_parser("gui-done")
    rel = sub.add_parser("release")
    rel.add_argument("--token", required=True, help="the lock token from preflight's run notes")
    sub.add_parser("forward-start")
    sub.add_parser("forward-stop")
    prefs = sub.add_parser("prefs-drift")
    prefs.add_argument("before")
    prefs.add_argument("baseline")
    sub.add_parser("ci-busy")
    hourly_p = sub.add_parser("hourly-checks")
    hourly_p.add_argument("--any-hour", action="store_true")
    log = sub.add_parser("hourly-log")
    log.add_argument("text")
    find = sub.add_parser("find-status-item")
    find.add_argument("--run-dir", required=True)
    opn = sub.add_parser("open-panel")
    opn.add_argument("--run-dir", required=True)
    opn.add_argument("--shot", default="")
    sub.add_parser("close-panel")
    cap = sub.add_parser("capture-status-item")
    cap.add_argument("--run-dir", required=True)
    cap.add_argument("--case-dir", required=True)
    hunt = sub.add_parser("hunt-checks")
    hunt.add_argument("--case-dir", required=True)
    hunt.add_argument("--fixture-text", default="", choices=["", "absent", "present"])
    ver = sub.add_parser("tc-cb-02-verdict")
    ver.add_argument("--run-dir", required=True)
    ver.add_argument("--case-dir", required=True)
    gp = sub.add_parser("grant-probe")
    gp.add_argument("--run-dir", required=True)
    gp.add_argument("--identity", required=True)
    gp.add_argument("--ref", required=True)
    gp.add_argument("--result", required=True, choices=["connected", "failed", "timeout"])
    gp.add_argument("--error-text", default="")
    gp.add_argument("--elapsed", type=float, default=0.0)
    hold_p = sub.add_parser("hold")
    hold_p.add_argument("--run", required=True)
    hold_p.add_argument("--release-file")
    hold_p.add_argument("--until", type=float)
    args = parser.parse_args(argv)
    lane = Lane()

    if args.cmd == "preflight":
        return print_result(preflight(lane, args.session))
    if args.cmd == "normalise":
        return print_result(normalise_after_dialogs(lane, args.token))
    if args.cmd == "case-gate":
        ok, reason = case_gate(lane, args.token)
        if reason == "lock-not-owned":
            reason = "time-budget lock-not-owned"
        print("ok" if ok else "BLOCKED %s %s" % (reason, args.case))
        return 0 if ok else 2
    if args.cmd == "restore":
        ok, notes = restore(lane, keep_marker=args.keep_marker)
        for line in notes:
            print("restore: %s" % line)
        print("RESTORED" if ok else "RESTORE-FAILED")
        return 0 if ok else 1
    if args.cmd == "gui-done":
        for line in gui_done(lane):
            print("restore: %s" % line)
        return 0
    if args.cmd == "release":
        ok, message = release_lock(lane, args.token)
        print(message)
        return 0 if ok else 1
    if args.cmd == "forward-start":
        ok, notes = start_forward(lane)
        for line in notes:
            print("forward: %s" % line)
        print("FORWARD-READY" if ok else "BLOCKED forward-failed")
        return 0 if ok else 2
    if args.cmd == "forward-stop":
        notes = []
        ok = stop_forward(lane, notes)
        for line in notes:
            print("forward: %s" % line)
        return 0 if ok else 1
    if args.cmd == "prefs-drift":
        keys = drift_files(args.before, args.baseline)
        print("drift: %s" % (", ".join(keys) if keys else "none"))
        return 1 if keys else 0
    if args.cmd == "ci-busy":
        busy, notes = ci_busy(lane)
        print("%s %s" % ("busy" if busy else "idle", " ".join(notes)))
        return 2 if busy else 0
    if args.cmd == "hourly-checks":
        result = hourly(lane, force_window=args.any_hour)
        print("%s %s" % (result["result"], ",".join(result["failures"])))
        return 0
    if args.cmd == "hourly-log":
        append_log(lane, args.text)
        return 0
    if args.cmd == "find-status-item":
        code, lines, _ = find_status_item(lane, Path(args.run_dir))
        print("\n".join(lines))
        return code
    if args.cmd == "open-panel":
        shot = Path(args.shot) if args.shot else Path(args.run_dir) / "02-panel-open.png"
        code, lines = open_panel(lane, Path(args.run_dir), shot)
        print("\n".join(lines))
        return code
    if args.cmd == "close-panel":
        close_panel(lane)
        return 0
    if args.cmd == "capture-status-item":
        code, lines = capture_status_item(lane, Path(args.run_dir), Path(args.case_dir))
        print("\n".join(lines))
        return code
    if args.cmd == "hunt-checks":
        code, lines = hunt_checks(lane, Path(args.case_dir), args.fixture_text)
        print("\n".join(lines))
        return code
    if args.cmd == "tc-cb-02-verdict":
        code, line = verdict(Path(args.run_dir), Path(args.case_dir))
        print(line)
        return code
    if args.cmd == "grant-probe":
        code, lines = grant_probe(lane, Path(args.run_dir), args.identity, args.ref, args.result,
                                  args.error_text, args.elapsed)
        print("\n".join(lines))
        return code
    if args.cmd == "hold":
        return hold(lane, args.run, args.release_file, args.until)
    return 1


if __name__ == "__main__":
    sys.exit(main())
