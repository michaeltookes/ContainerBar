#!/usr/bin/env python3
"""ContainerBar QA lane command line (CB-105). See README.md in this folder.

  preflight --session ID     step 0: CI wait, desktop lock, marker recovery
  normalise                  retry the quit/relaunch after closing dialogs
  case-gate [TC-ID]          before each case: time budget and CI, no wait
  restore [--keep-marker]    the no-GUI restore (containerbar-qa-restore.sh)
  release                    release the desktop lock held for this pass
  forward-start              Unix-socket leg: start the SSH-forwarded socket
  forward-stop               stop that forward by its recorded PID
  prefs-drift BEFORE BASE    step 0e: which baseline preferences drifted
  ci-busy                    print busy/idle and the predicate's notes
  hourly-checks              the launchd hourly check (run under the lock)
  hourly-log TEXT            append one line to hourly.log
  hold --run ID              internal: the lock holder's child process
Exit codes: 0 ok/ready, 1 failure, 2 blocked, 3 needs-normalise.
"""
from __future__ import annotations

import argparse
import sys

from lane_core import Lane, case_gate, ci_busy
from lane_hourly import append_log, hourly
from lane_preflight import hold, normalise_after_dialogs, preflight, print_result, release_lock
from lane_prefs import drift_files
from lane_restore import restore, start_forward, stop_forward


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    pre = sub.add_parser("preflight")
    pre.add_argument("--session", required=True)
    sub.add_parser("normalise")
    gate = sub.add_parser("case-gate")
    gate.add_argument("case", nargs="?", default="")
    rest = sub.add_parser("restore")
    rest.add_argument("--keep-marker", action="store_true")
    sub.add_parser("release")
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
    hold_p = sub.add_parser("hold")
    hold_p.add_argument("--run", required=True)
    hold_p.add_argument("--release-file")
    hold_p.add_argument("--until", type=float)
    args = parser.parse_args(argv)
    lane = Lane()

    if args.cmd == "preflight":
        return print_result(preflight(lane, args.session))
    if args.cmd == "normalise":
        return print_result(normalise_after_dialogs(lane))
    if args.cmd == "case-gate":
        ok, reason = case_gate(lane)
        print("ok" if ok else "BLOCKED %s %s" % (reason, args.case))
        return 0 if ok else 2
    if args.cmd == "restore":
        ok, notes = restore(lane, keep_marker=args.keep_marker)
        for line in notes:
            print("restore: %s" % line)
        print("RESTORED" if ok else "RESTORE-FAILED")
        return 0 if ok else 1
    if args.cmd == "release":
        ok = release_lock(lane)
        print("lock released" if ok else "lock still held")
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
    if args.cmd == "hold":
        return hold(lane, args.run, args.release_file, args.until)
    return 1


if __name__ == "__main__":
    sys.exit(main())
