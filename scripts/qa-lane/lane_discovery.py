"""Status-item and panel discovery for the ContainerBar QA lane (CB-137).

`peekaboo menubar list` and `peekaboo see --app` cannot see ContainerBar on the
agent Mini (the item is listed under neither, and the app has no regular
window). This module finds the item through the accessibility tree of the
released process, opens it, and captures the panel, modelled on the Sentwise
lane's explicit status-menu route (open the item, then capture the popover).

Only the released app is ever touched: the PID whose command starts
`/Applications/ContainerBar.app/`, never a hunt build. One BLOCKED line per
pass: the first failure is recorded in `<run>/status-item.json` and later calls
repeat it without a second BLOCKED line.

Python 3.9 compatible.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

from lane_core import APP_NAME, Lane, read_json, write_json

DISCOVERY_BUDGET_S = 10.0   # item must be found within 10 s
PANEL_BUDGET_S = 2.0        # panel must be open and captured within 2 s of the click
POLL_S = 1.0
DUMP_BUDGET_S = 5.0        # diagnostics after a failed pass are bounded too
PANEL_SIZE = (400, 720)     # fallback region under the item when AX gives no menu frame
STATE_FILE = "status-item.json"
DUMP_FILE = "ax-dump.txt"
FIELD = "|"

DISPLAYS_SCRIPT = (
    "ObjC.import('AppKit'); var s=$.NSScreen.screens; var h=s.objectAtIndex(0).frame.size.height; var o=[];"
    "for (var i=0;i<s.count;i++){var f=s.objectAtIndex(i).frame;"
    "o.push([f.origin.x,h-f.origin.y-f.size.height,f.size.width,f.size.height].join('|'));} o.join('\\n');")

# One line per menu bar item: bar index, item index, x, y, w, h, title, description, value.
AX_ITEMS_SCRIPT = """on run argv
set pid to (item 1 of argv) as integer
set AppleScript's text item delimiters to "|"
set out to {}
tell application "System Events"
 set p to first process whose unix id is pid
 set bars to count of menu bars of p
 repeat with b from 1 to bars
  set n to count of menu bar items of menu bar b of p
  repeat with i from 1 to n
   set mi to menu bar item i of menu bar b of p
   set pos to position of mi
   set sz to size of mi
   set end of out to (b as text) & "|" & (i as text) & "|" & ((item 1 of pos) as text) & "|" & ((item 2 of pos) as text) & "|" & ((item 1 of sz) as text) & "|" & ((item 2 of sz) as text) & "|" & ((title of mi) as text) & "|" & ((description of mi) as text) & "|" & ((value of mi) as text)
  end repeat
 end repeat
end tell
set AppleScript's text item delimiters to linefeed
return out as text
end run"""

# Panel frame (the status item's menu): x|y|w|h, empty when no menu is open.
AX_MENU_SCRIPT = """on run argv
set pid to (item 1 of argv) as integer
set AppleScript's text item delimiters to "|"
tell application "System Events"
 set p to first process whose unix id is pid
 try
  set m to menu 1 of menu bar item (item 2 of argv as integer) of menu bar (item 3 of argv as integer) of p
  set pos to position of m
  set sz to size of m
  return ((item 1 of pos) as text) & "|" & ((item 2 of pos) as text) & "|" & ((item 1 of sz) as text) & "|" & ((item 2 of sz) as text)
 on error
  return ""
 end try
end tell
end run"""

AX_PRESS_SCRIPT = """on run argv
set pid to (item 1 of argv) as integer
tell application "System Events"
 set p to first process whose unix id is pid
 click menu bar item (item 2 of argv as integer) of menu bar (item 3 of argv as integer) of p
end tell
end run"""

Item = Dict[str, object]


# ------------------------------------------------------------------ parsing


def parse_ax_items(text: str) -> List[Item]:
    """Parse AX_ITEMS_SCRIPT output into dicts; malformed lines are skipped."""
    items: List[Item] = []
    for line in text.splitlines():
        parts = line.split(FIELD)
        if len(parts) < 9:
            continue
        try:
            bar, index, x, y, w, h = (int(float(p)) for p in parts[:6])
        except ValueError:
            continue
        items.append({"bar": bar, "index": index, "frame": [x, y, w, h],
                      "title": parts[6].strip(), "description": parts[7].strip(),
                      "value": FIELD.join(parts[8:]).strip()})
    return items


def parse_frame(text: str) -> Optional[List[int]]:
    parts = [p.strip() for p in text.strip().split(FIELD)]
    if len(parts) != 4:
        return None
    try:
        frame = [int(float(p)) for p in parts]
    except ValueError:
        return None
    return frame if frame[2] > 0 and frame[3] > 0 else None


def is_containerbar(item: Item) -> bool:
    """The status item's AX description is `ContainerBar`; its title is the running count (e.g. `5`)."""
    return APP_NAME in (str(item.get("title", "")), str(item.get("axTitle", "")),
                        str(item.get("axDescription", "")), str(item.get("description", "")))


def is_status_item(item: Item) -> bool:
    """An AX menu bar item that is ContainerBar's status item, not its application menu (bar 1)."""
    frame = item.get("frame") or [0, 0, 0, 0]
    return (is_containerbar(item) and frame[2] > 0 and frame[3] > 0  # type: ignore[index]
            and (int(item.get("bar", 0)) >= 2 or "status menu" in str(item.get("description", ""))))


def peekaboo_frame(item: Item) -> Optional[List[int]]:
    """Peekaboo's `frame` is [[x, y], [w, h]]; return [x, y, w, h]."""
    try:
        (x, y), (w, h) = item["frame"]  # type: ignore[misc]
        return [int(x), int(y), int(w), int(h)]
    except (KeyError, TypeError, ValueError):
        return None


def center(frame: Sequence[int]) -> Tuple[int, int]:
    return frame[0] + frame[2] // 2, frame[1] + frame[3] // 2


def contains(outer: Sequence[int], point: Tuple[int, int]) -> bool:
    return outer[0] <= point[0] <= outer[0] + outer[2] and outer[1] <= point[1] <= outer[1] + outer[3]


# ------------------------------------------------------------------ sources


def peekaboo_bin(lane: Lane) -> str:
    configured = lane.setting("CBQA_PEEKABOO")
    if configured:
        return configured
    return "/opt/homebrew/bin/peekaboo" if os.path.exists("/opt/homebrew/bin/peekaboo") else "peekaboo"


def released_pids(lane: Lane, deadline: Optional[float] = None) -> List[int]:
    """PIDs of ContainerBar whose command starts with the released app path (never the hunt build)."""
    rc, out = lane.call(["pgrep", "-x", APP_NAME], 5, deadline)
    pids: List[int] = []
    if rc != 0:
        return pids
    prefix = lane.app_path.rstrip("/") + "/"
    for word in out.split():
        if not word.isdigit():
            continue
        rc, cmd = lane.call(["ps", "-o", "command=", "-p", word], 5, deadline)
        if rc == 0 and cmd.strip().startswith(prefix):
            pids.append(int(word))
    return pids


def hunt_running(lane: Lane, deadline: Optional[float] = None) -> bool:
    rc, out = lane.call(["pgrep", "-x", APP_NAME], 5, deadline)
    if rc != 0:
        return False
    return len(out.split()) > len(released_pids(lane, deadline))


def peekaboo_items(lane: Lane, deadline: Optional[float] = None) -> Tuple[List[Item], int]:
    """(ContainerBar entries, total entries) from `peekaboo menubar list --json`."""
    rc, out = lane.call([peekaboo_bin(lane), "menubar", "list", "--json"], 20, deadline)
    try:
        items = json.loads(out)["data"]["items"] if rc == 0 else []
    except (ValueError, KeyError, TypeError):
        items = []
    return [i for i in items if isinstance(i, dict) and is_containerbar(i)], len(items)


def ax_items(lane: Lane, pid: int, deadline: Optional[float] = None) -> List[Item]:
    rc, out = lane.call(["osascript", "-e", AX_ITEMS_SCRIPT, str(pid)], 20, deadline)
    return parse_ax_items(out) if rc == 0 else []


def ax_panel_frame(lane: Lane, pid: int, item: Item) -> Optional[List[int]]:
    rc, out = lane.run(["osascript", "-e", AX_MENU_SCRIPT, str(pid), str(item["index"]), str(item["bar"])], 10)
    return parse_frame(out) if rc == 0 else None


# ---------------------------------------------------------------- discovery


def discover_once(lane: Lane, deadline: Optional[float] = None) -> Dict[str, object]:
    """One look. Returns {"status": "found"|"missing"|"ambiguous", ...} with the evidence."""
    pids = released_pids(lane, deadline)
    peek, peek_total = peekaboo_items(lane, deadline)
    ax: List[Item] = []
    pid = pids[0] if len(pids) == 1 else 0
    if pid:
        ax = [i for i in ax_items(lane, pid, deadline) if is_status_item(i)]
    evidence = {"pids": pids, "menubar_total": peek_total, "menubar_matches": len(peek),
                "ax_matches": len(ax), "peekaboo": peek, "ax": ax}
    if len(pids) > 1 or len(ax) > 1:
        return dict(evidence, status="ambiguous")
    if len(ax) == 1:
        frame = list(ax[0]["frame"])  # type: ignore[arg-type]
        tied = [p for p in peek if contains(peekaboo_frame(p) or [0, 0, 0, 0], center(frame))]
        return dict(evidence, status="found", found_by="peekaboo" if tied else "ax",
                    frame=(peekaboo_frame(tied[0]) if tied else frame), pid=pid, item=ax[0])
    if len(peek) == 1 and pids and not hunt_running(lane, deadline):
        return dict(evidence, status="found", found_by="peekaboo", frame=peekaboo_frame(peek[0]),
                    pid=pids[0], item=None)
    if len(peek) > 1 or (peek and hunt_running(lane, deadline)):
        return dict(evidence, status="ambiguous")
    return dict(evidence, status="missing")


def save_dump(lane: Lane, run_dir: Path, result: Dict[str, object]) -> None:
    """The AX evidence for a blocked pass: every status item of the released PID, plus the Peekaboo counts."""
    run_dir.mkdir(parents=True, exist_ok=True)
    lines = ["released pids: %s" % ",".join(str(p) for p in result.get("pids", [])),  # type: ignore[union-attr]
             "menubar list: %s entries, %s match ContainerBar" % (result.get("menubar_total"),
                                                                 result.get("menubar_matches"))]
    for pid in result.get("pids", []):  # type: ignore[union-attr]
        lines.append("ax items of pid %s (bar|item|x|y|w|h|title|description|value):" % pid)
        for item in ax_items(lane, int(pid), lane.clock.now() + DUMP_BUDGET_S):
            frame = item["frame"]
            lines.append("  %s|%s|%s|%s|%s|%s|%s|%s|%s" % (item["bar"], item["index"], *frame, item["title"],
                                                           item["description"], item["value"]))  # type: ignore[misc]
    lines.append("peekaboo ContainerBar entries: %s" % json.dumps(result.get("peekaboo", []), sort_keys=True))
    (run_dir / DUMP_FILE).write_text("\n".join(lines) + "\n")


def blocked_line(reason: str, result: Dict[str, object]) -> str:
    return "BLOCKED %s menubar=%s ax=%s (ax-dump: %s)" % (
        reason, result.get("menubar_total", 0), result.get("ax_matches", 0), DUMP_FILE)


def find_status_item(lane: Lane, run_dir: Path) -> Tuple[int, List[str], Optional[Dict[str, object]]]:
    """Exit code (0 found, 2 blocked), lines to print, the found result.

    A pass that already reported BLOCKED answers `blocked <reason>` without a
    second BLOCKED line and without looking again.
    """
    state = read_json(run_dir / STATE_FILE)
    if state and state.get("status") == "blocked":
        return 2, ["blocked %s (already reported once this pass; see %s)" % (state.get("reason"), DUMP_FILE)], None
    deadline = lane.clock.now() + DISCOVERY_BUDGET_S
    while True:
        result = discover_once(lane, deadline)
        if result["status"] == "found" and lane.clock.now() > deadline:
            result = dict(result, status="missing")  # observed after the 10 s window: not accepted
        if result["status"] in ("found", "ambiguous") or lane.clock.now() >= deadline:
            break
        lane.clock.sleep(POLL_S)
        if lane.clock.now() >= deadline:
            break  # no probe left in the window; keep the last in-window evidence for the block
    if result["status"] == "found":
        frame = result["frame"]
        return 0, ["found-by: %s" % result["found_by"],
                   "frame: %s" % ",".join(str(v) for v in frame)], result  # type: ignore[union-attr]
    return _block(lane, run_dir, result, "status-item-ambiguous" if result["status"] == "ambiguous"
                  else "status-item-not-found")


def _block(lane: Lane, run_dir: Path, result: Dict[str, object],
           reason: str) -> Tuple[int, List[str], Optional[Dict[str, object]]]:
    save_dump(lane, run_dir, result)
    write_json(run_dir / STATE_FILE, {"status": "blocked", "reason": reason,
                                      "menubar": result.get("menubar_total"), "ax": result.get("ax_matches")})
    return 2, [blocked_line(reason, result)], None


# -------------------------------------------------------------------- panel


def displays(lane: Lane) -> List[List[int]]:
    """Display frames in top-left screen coordinates, from AppKit (never hard-coded)."""
    rc, out = lane.run(["osascript", "-l", "JavaScript", "-e", DISPLAYS_SCRIPT], 10)
    frames = [parse_frame(line) for line in out.splitlines()] if rc == 0 else []
    return [f for f in frames if f]


def display_for(frames: Sequence[Sequence[int]], point: Tuple[int, int]) -> Optional[List[int]]:
    for f in frames:
        if contains(f, point):
            return list(f)
    return None


def panel_region(item_frame: Sequence[int], menu_frame: Optional[Sequence[int]],
                 display: Optional[Sequence[int]] = None) -> List[int]:
    """The capture region: the panel's AX menu frame, else a rectangle under the item kept on its display."""
    if menu_frame:
        return list(menu_frame)
    x, y = item_frame[0] - 3, item_frame[1] + item_frame[3] + 4
    w, h = PANEL_SIZE
    if display:
        dx, dy, dw, dh = display
        w, h = min(w, dw), min(h, dh)
        x = max(dx, min(x, dx + dw - w))
        h = min(h, dy + dh - y)
    return [x, y, w, h]


def open_panel(lane: Lane, run_dir: Path, shot: Path) -> Tuple[int, List[str]]:
    """Find, open (positional click, AXPress when that does not open it) and capture the panel."""
    code, lines, found = find_status_item(lane, run_dir)
    if code != 0 or not found:
        return 2, lines
    pid, item, frame = found["pid"], found.get("item"), list(found["frame"])  # type: ignore[arg-type]
    ax = item or next((i for i in ax_items(lane, int(pid)) if is_status_item(i)), None)  # type: ignore[arg-type]
    cx, cy = center(frame)
    region_guess = panel_region(frame, None, display_for(displays(lane), (cx, cy)))
    before = shot.with_name(shot.stem + ".before.png")
    shot.parent.mkdir(parents=True, exist_ok=True)
    if before.exists():
        before.unlink()
    base_rc, _ = lane.run([peekaboo_bin(lane), "see", "--mode", "area", "--region",
                           ",".join(str(v) for v in region_guess), "--no-elements", "--path", str(before), "--json"], 20)
    have_base = base_rc == 0 and before.exists()
    start = lane.clock.now()
    lane.run([peekaboo_bin(lane), "click", "--at", "%d,%d" % (cx, cy), "--global", "--foreground",
              "--no-auto-focus"], 15)
    opened_by = "click"
    menu = _wait_menu(lane, int(pid), ax, start) if ax else None  # type: ignore[arg-type]
    if menu is None and ax:
        lane.run(["osascript", "-e", AX_PRESS_SCRIPT, str(pid), str(ax["index"]), str(ax["bar"])], 10)
        opened_by = "axpress"
        menu = _wait_menu(lane, int(pid), ax, lane.clock.now())  # type: ignore[arg-type]
    region = panel_region(frame, menu, display_for(displays(lane), (cx, cy)))
    source = "ax-menu" if menu else "region-under-item"
    rc, _ = lane.run([peekaboo_bin(lane), "see", "--mode", "area", "--region", ",".join(str(v) for v in region),
                      "--no-elements", "--path", str(shot), "--json"], 20)
    # Readiness is panel evidence: the AX menu frame, or a capture that differs from the pre-click region.
    # A missing baseline cannot establish that the panel opened.
    changed = shot.exists() and have_base and before.read_bytes() != shot.read_bytes()
    if before.exists():
        before.unlink()
    if rc != 0 or not shot.exists() or (menu is None and not changed):
        if shot.exists():
            shot.unlink()  # unverified region capture (desktop or another app): keep only the diagnostic text
        # Nothing opened (click and AXPress both tried), or no capture: one BLOCKED line for the pass.
        result = {"pids": [pid], "menubar_total": found.get("menubar_total", 0),
                  "ax_matches": found.get("ax_matches", 0), "peekaboo": found.get("peekaboo", [])}
        return _block(lane, run_dir, result, "panel-not-capturable")[:2]
    return 0, lines + ["opened-by: %s" % opened_by, "panel-capture: %s" % source,
                       "panel-region: %s" % ",".join(str(v) for v in region), "screenshot: %s" % shot]


def _wait_menu(lane: Lane, pid: int, ax: Item, start: float) -> Optional[List[int]]:
    """Poll the AX menu frame until it exists or the 2 s panel budget (from `start`) runs out."""
    while True:
        frame = ax_panel_frame(lane, pid, ax)
        if frame:
            return frame
        if lane.clock.now() - start >= PANEL_BUDGET_S:
            return None
        lane.clock.sleep(0.5)


def close_panel(lane: Lane) -> None:
    """Escape closes the open status menu (the click that opened it is not repeated)."""
    lane.run(["osascript", "-e", 'tell application "System Events" to key code 53'], 10)
