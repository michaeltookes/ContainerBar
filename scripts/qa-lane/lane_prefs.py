"""Step 0e preference comparison for the ContainerBar QA lane.

Compares a `defaults export com.tookes.ContainerBar` taken before the pass
with the private baseline plist. JSON-encoded values (dockerHosts,
containerSections) are compared decoded, so key order inside the stored JSON
never reads as drift; a key missing from either side compares as the app's
default (refreshInterval "10s", show stopped on, icon style containerCount),
matching SettingsStore's fallbacks, and launchAtLogin off. A key with no
default (SUSkippedVersion, SUHasLaunchedBefore) is drift when present on
one side only: a stray Skip This Version hides future updates.
"""
from __future__ import annotations

import json
import plistlib
from typing import Dict, List

DEFAULTS: Dict[str, object] = {
    "refreshInterval": "10s",
    "showStoppedContainers": True,
    "iconStyle": "containerCount",
    "launchAtLogin": False,
    "containerSections": [],
}
JSON_KEYS = ("dockerHosts", "containerSections")
# The architecture's allowlist (section 4); everything else in the domain is volatile.
COMPARED = ("refreshInterval", "showStoppedContainers", "launchAtLogin", "iconStyle",
            "dockerHosts", "selectedHostId", "containerSections",
            "SUEnableAutomaticChecks", "SUHasLaunchedBefore", "SUSkippedVersion")


def _value(prefs: Dict[str, object], key: str) -> object:
    value = prefs.get(key, DEFAULTS.get(key))
    if key in JSON_KEYS and isinstance(value, (bytes, bytearray, str)):
        try:
            value = json.loads(value)
        except ValueError:
            pass
    return value


def drift(before: Dict[str, object], baseline: Dict[str, object]) -> List[str]:
    return [key for key in COMPARED if _value(before, key) != _value(baseline, key)]


def drift_files(before_path: str, baseline_path: str) -> List[str]:
    with open(before_path, "rb") as handle:
        before = plistlib.load(handle)
    with open(baseline_path, "rb") as handle:
        baseline = plistlib.load(handle)
    return drift(before, baseline)
