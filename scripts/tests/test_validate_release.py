#!/usr/bin/env python3
"""
Tests for scripts/validate-release.py.

Covers the pure/parsing logic of the release validator without needing a real
release: the shell-injection guard on run(), the pass/fail accounting in
check(), and the version-matching checks for Info.plist, CHANGELOG, the
Homebrew cask, and the Sparkle appcast (both child-element and enclosure-
attribute shapes).

Runs two ways:
  * under pytest, if available:   pytest scripts/tests/test_validate_release.py
  * as a plain script (no deps):  python3 scripts/tests/test_validate_release.py

The mini has no pytest, so the __main__ runner below is the primary path.
NOTE: not wired into `swift test` — this exercises Python, not Swift.
"""

import importlib.util
import os
import plistlib
import tempfile
from contextlib import contextmanager
from unittest import mock

SCRIPT_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "validate-release.py",
)

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def load_module():
    """Load validate-release.py (hyphenated, so importlib by path) fresh."""
    spec = importlib.util.spec_from_file_location("validate_release_under_test", SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.passed = 0
    module.failed = 0
    return module


class FakeResponse:
    """Minimal context-manager stand-in for urllib's urlopen result."""

    def __init__(self, data):
        self._data = data

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self):
        return self._data


@contextmanager
def temp_file(content, suffix="", binary=False):
    mode = "wb" if binary else "w"
    fd, path = tempfile.mkstemp(suffix=suffix)
    os.close(fd)
    with open(path, mode) as handle:
        handle.write(content)
    try:
        yield path
    finally:
        os.unlink(path)


# ── run(): shell-injection guard ────────────────────────────────────────────

def test_run_rejects_shell_string():
    mod = load_module()
    raised = False
    try:
        mod.run("echo hi")
    except TypeError:
        raised = True
    assert raised, "run() must reject a shell command string"


def test_run_executes_argv():
    mod = load_module()
    rc, out = mod.run(["echo", "hello"])
    assert rc == 0
    assert out == "hello"


# ── check(): pass/fail accounting ───────────────────────────────────────────

def test_check_counts_pass_and_fail():
    mod = load_module()
    mod.check("a", True)
    mod.check("b", True)
    mod.check("c", False)
    assert mod.passed == 2
    assert mod.failed == 1


# ── check_info_plist ────────────────────────────────────────────────────────

def test_info_plist_matching_version_passes():
    mod = load_module()
    plist = {"CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "1200"}
    with temp_file(plistlib.dumps(plist), binary=True) as path:
        mod.INFO_PLIST = path
        mod.check_info_plist("1.2.0")
    # version match + non-empty build == two passes, zero failures.
    assert mod.passed == 2
    assert mod.failed == 0


def test_info_plist_version_mismatch_fails():
    mod = load_module()
    plist = {"CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "1200"}
    with temp_file(plistlib.dumps(plist), binary=True) as path:
        mod.INFO_PLIST = path
        mod.check_info_plist("9.9.9")
    assert mod.failed == 1  # version mismatch
    assert mod.passed == 1  # build still present


def test_info_plist_empty_build_fails():
    mod = load_module()
    plist = {"CFBundleShortVersionString": "1.2.0", "CFBundleVersion": ""}
    with temp_file(plistlib.dumps(plist), binary=True) as path:
        mod.INFO_PLIST = path
        mod.check_info_plist("1.2.0")
    assert mod.failed == 1  # empty build fails
    assert mod.passed == 1  # version matches


def test_info_plist_missing_file_fails_both():
    mod = load_module()
    mod.INFO_PLIST = "/nonexistent/Info.plist"
    mod.check_info_plist("1.2.0")
    assert mod.failed == 2


# ── check_changelog ─────────────────────────────────────────────────────────

def test_changelog_entry_found():
    mod = load_module()
    with temp_file("# Changelog\n\n## [1.2.0] - 2026-09-15\n- thing\n") as path:
        mod.CHANGELOG = path
        mod.check_changelog("1.2.0")
    assert mod.passed == 1 and mod.failed == 0


def test_changelog_entry_missing():
    mod = load_module()
    with temp_file("# Changelog\n\n## [1.1.0]\n") as path:
        mod.CHANGELOG = path
        mod.check_changelog("1.2.0")
    assert mod.failed == 1


def test_changelog_version_is_regex_escaped():
    # A version containing regex metacharacters must be matched literally, not
    # as a pattern. "1.2.0" already contains dots; assert a dot is not treated
    # as a wildcard by confirming "1x2x0" does NOT satisfy "1.2.0".
    mod = load_module()
    with temp_file("## [1x2x0]\n") as path:
        mod.CHANGELOG = path
        mod.check_changelog("1.2.0")
    assert mod.failed == 1, "dots in the version must be escaped, not wildcards"


# ── check_homebrew_cask ─────────────────────────────────────────────────────

def test_homebrew_cask_version_matches():
    mod = load_module()
    with temp_file('cask "containerbar" do\n  version "1.2.0"\nend\n') as path:
        mod.HOMEBREW_CASK = path
        mod.check_homebrew_cask("1.2.0")
    assert mod.passed == 1 and mod.failed == 0


def test_homebrew_cask_version_mismatch():
    mod = load_module()
    with temp_file('  version "0.9.0"\n') as path:
        mod.HOMEBREW_CASK = path
        mod.check_homebrew_cask("1.2.0")
    assert mod.failed == 1


def test_homebrew_cask_missing_file():
    mod = load_module()
    mod.HOMEBREW_CASK = "/nonexistent/containerbar.rb"
    mod.check_homebrew_cask("1.2.0")
    assert mod.failed == 1


# ── check_appcast ───────────────────────────────────────────────────────────

def _appcast_with_child(version):
    return (
        '<?xml version="1.0"?>'
        '<rss xmlns:sparkle="{ns}"><channel><item>'
        "<sparkle:shortVersionString>{v}</sparkle:shortVersionString>"
        '<enclosure url="x.zip"/>'
        "</item></channel></rss>"
    ).format(ns=SPARKLE_NS, v=version).encode()


def _appcast_with_enclosure_attr(version):
    return (
        '<?xml version="1.0"?>'
        '<rss xmlns:sparkle="{ns}"><channel><item>'
        '<enclosure url="x.zip" sparkle:shortVersionString="{v}"/>'
        "</item></channel></rss>"
    ).format(ns=SPARKLE_NS, v=version).encode()


def test_appcast_matches_child_element():
    mod = load_module()
    with mock.patch.object(mod.urllib.request, "urlopen",
                           return_value=FakeResponse(_appcast_with_child("2.0.4"))):
        mod.check_appcast("2.0.4")
    assert mod.passed == 1 and mod.failed == 0


def test_appcast_matches_enclosure_attribute():
    mod = load_module()
    with mock.patch.object(mod.urllib.request, "urlopen",
                           return_value=FakeResponse(_appcast_with_enclosure_attr("2.0.4"))):
        mod.check_appcast("2.0.4")
    assert mod.passed == 1 and mod.failed == 0


def test_appcast_missing_version_fails():
    mod = load_module()
    with mock.patch.object(mod.urllib.request, "urlopen",
                           return_value=FakeResponse(_appcast_with_child("1.0.0"))):
        mod.check_appcast("2.0.4")
    assert mod.failed == 1


def test_appcast_network_error_fails_gracefully():
    mod = load_module()
    with mock.patch.object(mod.urllib.request, "urlopen", side_effect=OSError("boom")):
        mod.check_appcast("2.0.4")
    assert mod.failed == 1  # exception is caught and recorded, not raised


# ── standalone runner (no pytest on the mini) ───────────────────────────────

def _run_all():
    tests = sorted(
        (name, obj)
        for name, obj in globals().items()
        if name.startswith("test_") and callable(obj)
    )
    failures = 0
    for name, fn in tests:
        try:
            fn()
            print("  [PASS] {}".format(name))
        except Exception as exc:  # noqa: BLE001 - report every failure
            failures += 1
            print("  [FAIL] {}: {}".format(name, exc))
    total = len(tests)
    print("\n  {}/{} python tests passed.".format(total - failures, total))
    return failures


if __name__ == "__main__":
    import sys
    sys.exit(1 if _run_all() else 0)
