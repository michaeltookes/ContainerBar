"""TC-CB-02 evidence for the ContainerBar QA lane (CB-138).

`capture-status-item` writes `01-status-item.png` (a region capture of the
reported frame plus a 4 px margin) and the item's AX value; `hunt-checks`
prints and records the three hunt lines verbatim; `tc-cb-02-verdict` reads the
case folder: all four evidence items present is PASS, any one missing is
`BLOCKED evidence-incomplete <item>` for TC-CB-02 only.

Python 3.9 compatible.
"""
from __future__ import annotations

from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

from lane_core import APP_NAME, Lane, read_json, write_json
from lane_launch import find_with_launch
from lane_discovery import (STATE_FILE, _block, ax_items, center, display_for, displays, find_status_item,
                            is_status_item, peekaboo_bin)

MARGIN = 4
MAX_STRIP_HEIGHT = 32
STRIP = "01-status-item.png"
PANEL = "02-panel-open.png"
AX_FILE = "status-item-ax.txt"
CAPTURE_FILE = "status-item-capture.json"
HUNT_FILE = "hunt-checks.txt"
HUNT_DOMAIN = "com.tookes.ContainerBar.hunt"
FIXTURE_VALUES = ("absent", "present")


def strip_region(frame: Sequence[int], display: Optional[Sequence[int]] = None) -> List[int]:
    """The frame plus a 4 px margin: at most frame width + 8 and 32 px tall, kept on its display."""
    fx, fy, fw, fh = frame
    w = fw + 2 * MARGIN
    h = min(fh + 2 * MARGIN, MAX_STRIP_HEIGHT)
    x, y = fx - MARGIN, fy - (h - fh) // 2
    if display:
        dx, dy, dw, dh = display
        w, h = min(w, dw), min(h, dh)
        x = max(dx, min(x, dx + dw - w))
        y = max(dy, min(y, dy + dh - h))
    return [x, y, w, h]


def usable_ax_value(value: str) -> bool:
    return bool(value.strip()) and value.strip() != "missing value"


def capture_status_item(lane: Lane, run_dir: Path, case_dir: Path) -> Tuple[int, List[str]]:
    """Find the item, capture its strip, record its AX title and value. Exit 0 ok, 2 blocked."""
    code, lines, found = find_with_launch(lane, run_dir)
    if code != 0 or not found:
        return 2, lines
    frame = list(found["frame"])  # type: ignore[arg-type]
    frames = displays(lane)
    display = display_for(frames, center(frame))
    if frames and display is None:
        # A confirmed off-screen frame: no evidence can be captured, and the pass blocks.
        return _block(lane, run_dir, found, "status-item-frame-missing")[:2]
    case_dir.mkdir(parents=True, exist_ok=True)
    strip = case_dir / STRIP
    if strip.exists():
        strip.unlink()
    if display is None:
        # The display lookup failed or timed out: case-local incomplete evidence, never a run-wide block.
        lines = lines + ["capture-failed: %s (display lookup failed)" % STRIP]
    else:
        region = strip_region(frame, display)
        rc, _ = lane.run([peekaboo_bin(lane), "see", "--mode", "area", "--region", ",".join(str(v) for v in region),
                          "--no-elements", "--path", str(strip), "--json"], 20)
        if rc != 0 or not strip.exists():
            if strip.exists():
                strip.unlink()
            lines = lines + ["capture-failed: %s" % STRIP]
        else:
            write_json(case_dir / CAPTURE_FILE, {"frame": frame, "region": region})
            lines = lines + ["strip: %s" % strip, "strip-region: %s" % ",".join(str(v) for v in region)]
    item = found.get("item")
    if not item and found.get("pid"):
        item = next((i for i in ax_items(lane, int(found["pid"])) if is_status_item(i)), None)  # type: ignore[arg-type]
    title = str(item.get("title", "")) if item else ""
    value = str(item.get("value", "")) if item else ""
    ax_path = case_dir / AX_FILE
    if ax_path.exists():
        ax_path.unlink()
    if item and usable_ax_value(value):
        ax_path.write_text("ax-title: %s\nax-value: %s\n" % (title, value))
        lines.append("ax-value: %s" % value)
    else:
        lines.append("ax-value: missing")
    return 0, lines


def _reason(rc: int) -> str:
    return "timeout" if rc == 124 else "rc=%s" % rc


def _hunt_process(lane: Lane) -> str:
    """`none`, a hunt PID, or `error <reason>`: one enumeration, every probe failure is an error."""
    rc, out = lane.run(["pgrep", "-x", APP_NAME], 5)
    if rc == 1:
        return "none"
    if rc != 0:
        return "error pgrep %s" % _reason(rc)
    prefix = lane.app_path.rstrip("/") + "/"
    hunters = []
    for word in out.split():
        if not word.isdigit():
            continue
        rc, cmd = lane.run(["ps", "-o", "command=", "-p", word], 5)
        if rc != 0:
            return "error ps %s" % _reason(rc)
        if not cmd.strip().startswith(prefix):
            hunters.append(word)
    return hunters[0] if hunters else "none"


def hunt_checks(lane: Lane, case_dir: Path, fixture_text: str) -> Tuple[int, List[str]]:
    """The hunt lines, recorded verbatim in hunt-checks.txt and printed.

    hunt-process: `none`, or the PID of a ContainerBar process that is not the released app.
    hunt-sparkle: `absent` (no defaults domain or key) or the SULastCheckTime value.
    hunt-fixture-text: the caller's reading of the released panel capture (absent|present).
    """
    process = _hunt_process(lane)
    rc, out = lane.run(["defaults", "read", HUNT_DOMAIN, "SULastCheckTime"], 5)
    if rc == 0 and out.strip():
        sparkle = out.strip()
    elif rc in (0, 1):  # a missing domain or key is a normal exit 1
        sparkle = "absent"
    else:
        sparkle = "error %s" % _reason(rc)
    lines = ["hunt-process: %s" % process,
             "hunt-sparkle: %s" % sparkle,
             "hunt-fixture-text: %s" % (fixture_text if fixture_text in FIXTURE_VALUES else "unknown")]
    case_dir.mkdir(parents=True, exist_ok=True)
    (case_dir / HUNT_FILE).write_text("\n".join(lines) + "\n")
    return 0, lines


def parse_hunt(text: str) -> Dict[str, str]:
    out: Dict[str, str] = {}
    for line in text.splitlines():
        key, sep, value = line.partition(":")
        if sep and key.strip() in ("hunt-process", "hunt-sparkle", "hunt-fixture-text") and value.strip():
            out[key.strip()] = value.strip()
    return out


def verdict(run_dir: Path, case_dir: Path) -> Tuple[int, str]:
    """PASS (0), `FAIL P1` (1), or BLOCKED (2) for TC-CB-02; never touches another case."""
    state = read_json(run_dir / STATE_FILE)
    if state and state.get("status") == "blocked":
        return 2, "BLOCKED %s (see ax-dump.txt)" % state.get("reason")
    missing = []
    capture = read_json(case_dir / CAPTURE_FILE) or {}
    frame, region = capture.get("frame"), capture.get("region")
    strip_ok = (case_dir / STRIP).exists() and bool(frame) and bool(region)
    if strip_ok:
        strip_ok = region[2] <= frame[2] + 2 * MARGIN and region[3] <= MAX_STRIP_HEIGHT  # type: ignore[index]
    if not strip_ok:
        missing.append(STRIP)
    if not (case_dir / PANEL).exists():
        missing.append(PANEL)
    ax_file = case_dir / AX_FILE
    ax_value = ax_file.read_text().partition("ax-value:")[2].strip() if ax_file.exists() else ""
    if not usable_ax_value(ax_value):
        missing.append("ax-value")
    hunt = parse_hunt((case_dir / HUNT_FILE).read_text()) if (case_dir / HUNT_FILE).exists() else {}
    errored = any(hunt.get(k, "").startswith("error") for k in ("hunt-process", "hunt-sparkle"))
    if len(hunt) < 3 or errored or hunt.get("hunt-fixture-text") not in FIXTURE_VALUES:
        missing.append("hunt-checks")
    if missing:
        return 2, "BLOCKED evidence-incomplete %s" % missing[0]
    if hunt["hunt-fixture-text"] == "present":
        return 1, "FAIL P1 hunt-fixture-text present (CB-090)"
    return 0, "PASS"
