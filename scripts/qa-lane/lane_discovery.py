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

import lane_pixels
from lane_core import APP_NAME, Lane, read_json, write_json

LIVENESS_S = 5   # System Events liveness bound (CB-141)
LIVENESS_SCRIPT = 'tell application "System Events" to count processes'
DISCOVERY_BUDGET_S = 10.0   # item must be found within 10 s
PANEL_BUDGET_S = 2.0        # panel must be open and captured within 2 s of the click (one absolute deadline)
CLICK_WINDOW_S = 1.0        # the click gets this long before the AXPress fallback; AXPress shares the same deadline
RETRY_GAP_S = 1.0           # Escape, then this long, before the one second attempt (CB-143)
PANEL_POLL_S = 0.5
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


class AxTimeout(Exception):
    """System Events did not answer in time (CB-141): a hang is not "no items"."""

    def __init__(self, seconds: float):
        super().__init__("ax-timeout %ss" % seconds)
        self.seconds = seconds


def ax_items(lane: Lane, pid: int, deadline: Optional[float] = None, strict: bool = False) -> List[Item]:
    budget = 20.0 if deadline is None else min(20.0, deadline - lane.clock.now())
    rc, out = lane.call(["osascript", "-e", AX_ITEMS_SCRIPT, str(pid)], 20, deadline)
    if strict and rc == 124 and budget > 0:  # the call really ran and hung; past the deadline nothing ran
        raise AxTimeout(int(round(budget)))
    return parse_ax_items(out) if rc == 0 else []


def system_events_alive(lane: Lane) -> bool:
    """One trivial Apple Event bounded at LIVENESS_S; only a timeout (124) counts as not answering."""
    rc, _ = lane.run(["osascript", "-e", LIVENESS_SCRIPT], LIVENESS_S)
    return rc != 124


def ax_panel_frame(lane: Lane, pid: int, item: Item, deadline: Optional[float] = None) -> Optional[List[int]]:
    """The AX menu frame, or None. With a deadline the call is capped to it and an answer after it is rejected."""
    rc, out = lane.call(["osascript", "-e", AX_MENU_SCRIPT, str(pid), str(item["index"]), str(item["bar"])],
                        10, deadline)
    if deadline is not None and lane.clock.now() > deadline:
        return None
    return parse_frame(out) if rc == 0 else None


# ---------------------------------------------------------------- discovery


def discover_once(lane: Lane, deadline: Optional[float] = None) -> Dict[str, object]:
    """One look. Returns {"status": "found"|"missing"|"ambiguous", ...} with the evidence."""
    pids = released_pids(lane, deadline)
    peek, peek_total = peekaboo_items(lane, deadline)
    ax: List[Item] = []
    pid = pids[0] if len(pids) == 1 else 0
    if pid:
        ax = [i for i in ax_items(lane, pid, deadline, strict=True) if is_status_item(i)]
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
    if not system_events_alive(lane):
        return _block_timeout(lane, run_dir, LIVENESS_S)
    deadline = lane.clock.now() + DISCOVERY_BUDGET_S
    while True:
        try:
            result = discover_once(lane, deadline)
        except AxTimeout as exc:
            return _block_timeout(lane, run_dir, exc.seconds)
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


def _block_timeout(lane: Lane, run_dir: Path, seconds: float) -> Tuple[int, List[str], Optional[Dict[str, object]]]:
    """BLOCKED ax-timeout: System Events did not answer. No further AX call is made for the dump."""
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / DUMP_FILE).write_text("ax-timeout: System Events did not answer within %ss; discovery ran no "
                                     "further AX call (run it from the agent shell, not a LaunchAgent)\n" % seconds)
    write_json(run_dir / STATE_FILE, {"status": "blocked", "reason": "ax-timeout", "menubar": None, "ax": None})
    return 2, ["BLOCKED ax-timeout system-events %ss (ax-dump: %s)" % (seconds, DUMP_FILE)], None


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


def _capture(lane: Lane, see: List[str], region: Sequence[int], path: Path, deadline: float) -> bool:
    """One area capture inside the deadline; True only if it ran, wrote the file and finished in time."""
    rc, _ = lane.call(see + [",".join(str(v) for v in region), "--no-elements", "--path", str(path), "--json"],
                      20, deadline)
    return rc == 0 and path.exists() and lane.clock.now() <= deadline


def _ms(seconds: float) -> int:
    return int(round(seconds * 1000))


def _attempt(lane: Lane, found: Dict[str, object], ax: Optional[Item], region_guess: List[int],
             before: Path, have_base: bool, wide: Optional[lane_pixels.Image], display: Optional[List[int]],
             shot: Path, see: List[str]) -> Dict[str, object]:
    """One open-and-capture attempt with its own PANEL_BUDGET_S, measured from its click (CB-138, CB-143).

    Returns the attempt record (ok, opened_by, source, region plus the diagnostics written to ax-dump.txt).
    A probe is recorded as run only if its command was dispatched; one that found no budget left is counted as
    skipped (Lane.call returns 124 without running it once the deadline has passed).
    """
    pid, (cx, cy) = found["pid"], center(list(found["frame"]))  # type: ignore[arg-type]
    # One absolute deadline from the moment the click is dispatched: the click itself, the AX frame, the
    # AXPress fallback, every probe and the capture all run inside it, with their timeouts capped to
    # what is left, so a slow click cannot extend the evidence window (CB-138).
    start = lane.clock.now()
    deadline = start + PANEL_BUDGET_S
    click_rc, _ = lane.call([peekaboo_bin(lane), "click", "--at", "%d,%d" % (cx, cy), "--global", "--foreground",
                             "--no-auto-focus"], 15, deadline)
    rec: Dict[str, object] = {"ok": False, "opened_by": "click", "source": "", "region": [], "click_rc": click_rc,
                              "click_ms": _ms(lane.clock.now() - start), "axpress": "no", "menu_ms": None,
                              "changed": "no-baseline" if not have_base else "no",
                              "menu_run": 0, "menu_skip": 0, "check_run": 0, "check_skip": 0}
    pressed, changed = False, False

    def dispatch(kind: str) -> bool:
        """True if budget is left to dispatch a probe; otherwise count it as skipped for lack of budget."""
        if lane.clock.now() < deadline:
            rec[kind + "_run"] = int(rec[kind + "_run"]) + 1  # type: ignore[call-overload]
            return True
        rec[kind + "_skip"] = int(rec[kind + "_skip"]) + 1  # type: ignore[call-overload]
        return False

    def capture(region: Sequence[int], path: Path) -> bool:
        return dispatch("check") and _capture(lane, see, region, path, deadline)

    def region_changed() -> bool:
        # Readiness without an AX menu frame: the region under the item differs from the pre-click capture.
        if capture(region_guess, shot) and before.read_bytes() != shot.read_bytes():
            rec["changed"] = "yes"
            return True
        return False

    def menu_differs() -> Optional[bool]:
        """Does the capture of the AX menu's rectangle differ from the baseline of that same rectangle?

        Baseline design: the exact region_guess capture when the menu is that region, else the wide pre-click
        capture of the whole display, decoded and cropped to the menu rectangle (scale = pixels per point).
        None when no baseline covers the rectangle: the caller records no-baseline and fails.
        """
        if list(menu_rect) == list(region_guess):
            return before.read_bytes() != shot.read_bytes()
        if wide is None or display is None:
            return None
        dx, dy, dw, dh = display
        mx, my, mw, mh = menu_rect
        scale = wide.width / float(dw)
        got = lane_pixels.decode(shot)
        if got is None or abs(got.width - mw * scale) > 2 or abs(got.height - mh * scale) > 2:
            return None
        base = wide.crop(int(round((mx - dx) * scale)), int(round((my - dy) * scale)), got.width, got.height)
        return None if base is None else not base.same_pixels(got)

    def menu_verified(menu: List[int]) -> bool:
        # CB-143: an AX menu frame alone proves nothing (2026-11-19: unrelated desktop content). The capture
        # counts only if the same rectangle looked different before the click.
        nonlocal menu_rect
        if not have_base or not capture(menu, shot):
            return False
        menu_rect = menu
        differs = menu_differs()
        if differs is None:
            rec["changed"] = "no-baseline"
            return False
        rec["changed"] = "yes" if differs else "no"
        return differs

    menu_rect: List[int] = []
    menu_ok: Optional[List[int]] = None
    while lane.clock.now() < deadline:
        if ax:
            menu = ax_panel_frame(lane, int(pid), ax, deadline) if dispatch("menu") else None  # type: ignore[arg-type]
            if menu:
                if rec["menu_ms"] is None:
                    rec["menu_ms"] = _ms(lane.clock.now() - start)
                if menu_verified(menu):
                    menu_ok = menu
                    break
                if shot.exists():
                    shot.unlink()  # AX says a menu, the pixels say nothing was drawn (or no baseline)
            elif not pressed and lane.clock.now() - start >= CLICK_WINDOW_S:
                if have_base and region_changed():
                    changed = True  # the click already opened it: a second press could close it again
                    break
                if lane.clock.now() >= deadline:
                    rec["axpress"] = "skipped (no budget)"  # never dispatched: do not say it ran
                    break
                lane.call(["osascript", "-e", AX_PRESS_SCRIPT, str(pid), str(ax["index"]), str(ax["bar"])], 10, deadline)
                rec["opened_by"], rec["axpress"], pressed = "axpress", "yes", True
                continue  # look at the AX menu again straight away; the timer is not reset
        if (not ax or pressed) and have_base and region_changed():
            changed = True
            break
        lane.clock.sleep(PANEL_POLL_S)
    if menu_ok:
        rec.update(ok=True, source="ax-menu", region=list(menu_ok))
    elif changed:
        rec.update(ok=True, source="region-under-item", region=list(region_guess))
    if rec["changed"] == "no" and not rec["check_run"] and rec["check_skip"]:
        rec["changed"] = "not-checked (no budget)"
    if not rec["ok"] and shot.exists():
        shot.unlink()  # unverified capture (desktop or another app): keep only the diagnostic text
    rec["elapsed_ms"] = _ms(lane.clock.now() - start)
    return rec


def _probes(run: object, skip: object, noun: str) -> str:
    text = "%s %s" % (run, noun if run == 1 else noun + "s")
    return text + (", %s skipped (no budget)" % skip if skip else "")


def _attempt_lines(attempts: Sequence[Dict[str, object]], have_base: bool, have_wide: bool,
                   escape_rc: Optional[object]) -> List[str]:
    lines = ["open-panel attempts: %d, budget %d ms each, %d ms gap with Escape; baseline: %s; wide baseline: %s" % (
        len(attempts), _ms(PANEL_BUDGET_S), _ms(RETRY_GAP_S), "yes" if have_base else "no",
        "yes" if have_wide else "no")]
    for n, rec in enumerate(attempts, 1):
        if rec["menu_ms"] is not None:
            menu = "seen at %s ms" % rec["menu_ms"]
        elif rec["menu_run"]:
            menu = "never (%s)" % _probes(rec["menu_run"], rec["menu_skip"], "probe")
        else:
            menu = "not probed (no budget)" if rec["menu_skip"] else "not probed (no AX item)"
        lines += ["attempt %d:" % n, "  click rc: %s (returned at %s ms)" % (rec["click_rc"], rec["click_ms"]),
                  "  axpress: %s" % rec["axpress"], "  ax-menu: %s" % menu,
                  "  region-changed: %s" % rec["changed"],
                  "  captures: %s" % _probes(rec["check_run"], rec["check_skip"], "capture"),
                  "  elapsed: %s ms" % rec["elapsed_ms"]]
        if n == 1 and len(attempts) > 1:
            lines.append("  escape rc before attempt 2: %s" % escape_rc)
    return lines


def open_panel(lane: Lane, run_dir: Path, shot: Path) -> Tuple[int, List[str]]:
    """Find, open (positional click, AXPress when that does not open it) and capture the panel.

    Two attempts at most (CB-143): the second after Escape and RETRY_GAP_S, each with its own PANEL_BUDGET_S,
    so the command ends within 2 + 1 + 2 = 5 s of the first click. A block records every attempt in ax-dump.txt.
    Baselines are taken before the first click, outside that bound: the region under the item (exact compare)
    and the whole display (decoded and cropped to an AX menu frame that lies elsewhere).
    """
    code, lines, found = find_status_item(lane, run_dir)
    if code != 0 or not found:
        return 2, lines
    pid, item, frame = found["pid"], found.get("item"), list(found["frame"])  # type: ignore[arg-type]
    ax = item or next((i for i in ax_items(lane, int(pid)) if is_status_item(i)), None)  # type: ignore[arg-type]
    cx, cy = center(frame)
    display = display_for(displays(lane), (cx, cy))
    region_guess = panel_region(frame, None, display)
    before = shot.with_name(shot.stem + ".before.png")
    wide_path = shot.with_name(shot.stem + ".wide.png")
    shot.parent.mkdir(parents=True, exist_ok=True)
    for stale in (before, wide_path):
        if stale.exists():
            stale.unlink()
    see = [peekaboo_bin(lane), "see", "--mode", "area", "--region"]
    base_rc, _ = lane.run(see + [",".join(str(v) for v in region_guess), "--no-elements", "--path", str(before),
                                 "--json"], 20)
    have_base = base_rc == 0 and before.exists()
    wide: Optional[lane_pixels.Image] = None
    if have_base and display:
        wide_rc, _ = lane.run(see + [",".join(str(v) for v in display), "--no-elements", "--path", str(wide_path),
                                     "--json"], 20)
        wide = lane_pixels.decode(wide_path) if wide_rc == 0 else None
        if wide_path.exists():
            wide_path.unlink()
    attempts: List[Dict[str, object]] = []
    escape_rc: object = None
    for n in range(1, 3):
        if n == 2:
            # Close any half-open menu, then wait out the gap. The pre-click baselines are kept: Escape restores
            # the screen they were taken from, and a new capture here would spend time the 5 s bound does not have.
            gap_end = lane.clock.now() + RETRY_GAP_S
            if lane.clock.now() < gap_end:
                escape_rc, _ = lane.call(["osascript", "-e", 'tell application "System Events" to key code 53'], 10,
                                         gap_end)
            else:
                escape_rc = "skipped (no budget)"
            if gap_end > lane.clock.now():
                lane.clock.sleep(gap_end - lane.clock.now())
        rec = _attempt(lane, found, ax, region_guess, before, have_base, wide, display, shot, see)
        attempts.append(rec)
        if rec["ok"]:
            break
    if before.exists():
        before.unlink()
    last = attempts[-1]
    if not last["ok"]:
        result = {"pids": [pid], "menubar_total": found.get("menubar_total", 0),
                  "ax_matches": found.get("ax_matches", 0), "peekaboo": found.get("peekaboo", [])}
        out = _block(lane, run_dir, result, "panel-not-capturable")[:2]
        with (run_dir / DUMP_FILE).open("a") as fh:
            fh.write("\n".join(_attempt_lines(attempts, have_base, wide is not None, escape_rc)) + "\n")
        return out
    return 0, lines + ["opened-by: %s" % last["opened_by"], "attempt: %d" % len(attempts),
                       "panel-capture: %s" % last["source"],
                       "panel-region: %s" % ",".join(str(v) for v in last["region"]),  # type: ignore[union-attr]
                       "screenshot: %s" % shot]


def close_panel(lane: Lane) -> None:
    """Escape closes the open status menu (the click that opened it is not repeated)."""
    lane.run(["osascript", "-e", 'tell application "System Events" to key code 53'], 10)
