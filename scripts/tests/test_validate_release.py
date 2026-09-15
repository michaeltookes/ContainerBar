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
  * in CI as a standalone step:   python3 scripts/tests/test_validate_release.py

The mini has no pytest, so the __main__ runner below is the primary path.
NOTE: intentionally separate from `swift test` — this exercises Python, not Swift.
"""

import hashlib
import importlib.util
import json
import os
import plistlib
import tempfile
import types
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
    module.skipped = 0
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


def fake_completed(stdout="", stderr="", returncode=0):
    """Stand-in for subprocess.run's CompletedProcess (only fields we read)."""
    return types.SimpleNamespace(stdout=stdout, stderr=stderr, returncode=returncode)


def _make_app_side_effect(app_name):
    """Return a side_effect that mimics extract/attach by creating <name>.app."""
    def _side_effect(_src, dest):
        os.makedirs(os.path.join(dest, f"{app_name}.app"), exist_ok=True)
        return True
    return _side_effect


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


# ── GitHub release asset digests ────────────────────────────────────────────

def test_github_release_asset_sha256_uses_release_digest():
    mod = load_module()
    digest = "a" * 64
    with mock.patch.object(mod, "run", return_value=(0, f"sha256:{digest}\n")), \
         mock.patch.object(mod, "_download_github_release_asset_sha256") as download:
        actual, detail = mod.github_release_asset_sha256("2.0.4")

    assert actual == digest
    assert detail == ""
    assert not download.called


def test_github_release_asset_sha256_downloads_when_digest_absent():
    mod = load_module()
    digest = "b" * 64
    with mock.patch.object(mod, "run", return_value=(0, "")), \
         mock.patch.object(mod, "_download_github_release_asset_sha256",
                           return_value=(digest, "")) as download:
        actual, detail = mod.github_release_asset_sha256("2.0.4")

    assert actual == digest
    assert detail == ""
    download.assert_called_once_with("v2.0.4")


def test_download_github_release_asset_sha256_hashes_uploaded_asset():
    mod = load_module()
    payload = b"uploaded-release-zip"
    expected = hashlib.sha256(payload).hexdigest()

    def fake_download(cmd):
        workdir = cmd[cmd.index("--dir") + 1]
        with open(os.path.join(workdir, mod.RELEASE_ZIP_ASSET), "wb") as handle:
            handle.write(payload)
        return 0, ""

    with mock.patch.object(mod, "run", side_effect=fake_download):
        actual, detail = mod._download_github_release_asset_sha256("v2.0.4")

    assert actual == expected
    assert detail == ""


def test_download_github_release_asset_sha256_reports_download_failure():
    mod = load_module()
    with mock.patch.object(mod, "run", return_value=(1, "")):
        actual, detail = mod._download_github_release_asset_sha256("v2.0.4")

    assert actual == ""
    assert "could not download" in detail


def test_github_release_assets_parses_asset_metadata():
    mod = load_module()
    assets = [{"name": mod.RELEASE_ZIP_ASSET}, {"name": mod.RELEASE_DMG_ASSET}]
    with mock.patch.object(mod, "run", return_value=(0, json.dumps({"assets": assets}))):
        release_found, actual, detail = mod.github_release_assets("2.0.4")

    assert release_found
    assert actual == assets
    assert detail == ""


def test_github_release_requires_zip_and_dmg_assets():
    mod = load_module()
    assets = [{"name": mod.RELEASE_ZIP_ASSET}, {"name": mod.RELEASE_DMG_ASSET}]
    with mock.patch.object(mod, "github_release_assets", return_value=(True, assets, "")):
        mod.check_github_release("2.0.4")

    assert mod.passed == 3 and mod.failed == 0


def test_github_release_fails_when_dmg_asset_missing():
    mod = load_module()
    assets = [{"name": mod.RELEASE_ZIP_ASSET}]
    with mock.patch.object(mod, "github_release_assets", return_value=(True, assets, "")):
        mod.check_github_release("2.0.4")

    assert mod.passed == 2
    assert mod.failed == 1


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


# ── check_gatekeeper_zip ────────────────────────────────────────────────────

def test_gatekeeper_zip_skips_when_absent():
    mod = load_module()
    mod.RELEASE_ZIP = "/nonexistent/ContainerBar.zip"
    mod.check_gatekeeper_zip()
    assert mod.skipped == 1
    assert mod.passed == 0 and mod.failed == 0


def test_gatekeeper_zip_accepted():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        mod.RELEASE_ZIP = zip_path
        with mock.patch.object(mod, "_extract_zip", side_effect=_make_app_side_effect(mod.APP_NAME)), \
             mock.patch.object(mod.subprocess, "run",
                               return_value=fake_completed(stderr="source=Notarized Developer ID\naccepted\n")):
            mod.check_gatekeeper_zip()
    assert mod.passed == 1 and mod.failed == 0 and mod.skipped == 0


def test_gatekeeper_zip_rejected():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        mod.RELEASE_ZIP = zip_path
        with mock.patch.object(mod, "_extract_zip", side_effect=_make_app_side_effect(mod.APP_NAME)), \
             mock.patch.object(mod.subprocess, "run",
                               return_value=fake_completed(stderr="rejected\n", returncode=3)):
            mod.check_gatekeeper_zip()
    assert mod.failed == 1 and mod.passed == 0


def test_gatekeeper_zip_extract_failure_fails():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        mod.RELEASE_ZIP = zip_path
        with mock.patch.object(mod, "_extract_zip", return_value=False):
            mod.check_gatekeeper_zip()
    assert mod.failed == 1


# ── check_dmg_contents ──────────────────────────────────────────────────────

def test_dmg_skips_when_absent():
    mod = load_module()
    mod.RELEASE_DMG = "/nonexistent/ContainerBar.dmg"
    mod.check_dmg_contents()
    assert mod.skipped == 1
    assert mod.passed == 0 and mod.failed == 0


def test_dmg_contains_app():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        mod.RELEASE_DMG = dmg_path
        with mock.patch.object(mod, "_attach_dmg", side_effect=_make_app_side_effect(mod.APP_NAME)), \
             mock.patch.object(mod, "_detach_dmg") as detach:
            mod.check_dmg_contents()
            assert detach.called, "a mounted DMG must always be detached"
    assert mod.passed == 1 and mod.failed == 0 and mod.skipped == 0


def test_dmg_missing_app_fails():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        mod.RELEASE_DMG = dmg_path
        # attaches successfully but the mountpoint has no .app
        with mock.patch.object(mod, "_attach_dmg", return_value=True), \
             mock.patch.object(mod, "_detach_dmg") as detach:
            mod.check_dmg_contents()
            assert detach.called
    assert mod.failed == 1


def test_dmg_attach_failure_does_not_detach():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        mod.RELEASE_DMG = dmg_path
        with mock.patch.object(mod, "_attach_dmg", return_value=False), \
             mock.patch.object(mod, "_detach_dmg") as detach:
            mod.check_dmg_contents()
            assert not detach.called, "no attach means nothing to detach"
    assert mod.failed == 1


# ── check_cask_sha256 ───────────────────────────────────────────────────────

def test_cask_sha256_matches_uploaded_release_asset():
    mod = load_module()
    digest = "c" * 64
    with temp_file(f'cask "containerbar" do\n  sha256 "{digest}"\nend\n') as cask_path:
        mod.RELEASE_ZIP = "/nonexistent/ContainerBar.zip"
        mod.HOMEBREW_CASK = cask_path
        with mock.patch.object(mod, "github_release_asset_sha256",
                               return_value=(digest, "")) as asset_sha:
            mod.check_cask_sha256("2.0.4")

    asset_sha.assert_called_once_with("2.0.4")
    assert mod.passed == 1 and mod.failed == 0


def test_cask_sha256_mismatch():
    mod = load_module()
    with temp_file('  sha256 "{}"\n'.format("0" * 64)) as cask_path:
        mod.HOMEBREW_CASK = cask_path
        with mock.patch.object(mod, "github_release_asset_sha256", return_value=("d" * 64, "")):
            mod.check_cask_sha256("2.0.4")
    assert mod.failed == 1


def test_cask_sha256_fails_when_release_asset_digest_unavailable():
    mod = load_module()
    with temp_file('  sha256 "{}"\n'.format("0" * 64)) as cask_path:
        mod.HOMEBREW_CASK = cask_path
        with mock.patch.object(mod, "github_release_asset_sha256",
                               return_value=("", "asset digest unavailable")):
            mod.check_cask_sha256("2.0.4")
    assert mod.failed == 1 and mod.passed == 0 and mod.skipped == 0


def test_cask_sha256_skips_when_cask_absent():
    mod = load_module()
    mod.HOMEBREW_CASK = "/nonexistent/containerbar.rb"
    with mock.patch.object(mod, "github_release_asset_sha256") as asset_sha:
        mod.check_cask_sha256("2.0.4")

    assert not asset_sha.called
    assert mod.skipped == 1 and mod.passed == 0 and mod.failed == 0


# ── check_cask_arm64 ────────────────────────────────────────────────────────

def test_cask_arm64_present():
    mod = load_module()
    with temp_file('cask "containerbar" do\n  depends_on arch: :arm64\nend\n') as cask_path:
        mod.HOMEBREW_CASK = cask_path
        mod.check_cask_arm64()
    assert mod.passed == 1 and mod.failed == 0


def test_cask_arm64_missing_fails():
    mod = load_module()
    with temp_file('cask "containerbar" do\n  version "2.0.4"\nend\n') as cask_path:
        mod.HOMEBREW_CASK = cask_path
        mod.check_cask_arm64()
    assert mod.failed == 1


def test_cask_arm64_skips_when_absent():
    mod = load_module()
    mod.HOMEBREW_CASK = "/nonexistent/containerbar.rb"
    mod.check_cask_arm64()
    assert mod.skipped == 1 and mod.passed == 0 and mod.failed == 0


# ── check_appcast_signature ─────────────────────────────────────────────────

def _appcast_with_enclosure(version, ed_signature=None, length=None):
    sig_attr = ' sparkle:edSignature="{}"'.format(ed_signature) if ed_signature is not None else ""
    len_attr = ' length="{}"'.format(length) if length is not None else ""
    return (
        '<?xml version="1.0"?>'
        '<rss xmlns:sparkle="{ns}"><channel><item>'
        "<sparkle:shortVersionString>{v}</sparkle:shortVersionString>"
        '<enclosure url="ContainerBar.zip"{sig}{ln}/>'
        "</item></channel></rss>"
    ).format(ns=SPARKLE_NS, v=version, sig=sig_attr, ln=len_attr)


def test_appcast_signature_and_length_ok():
    mod = load_module()
    payload = b"x" * 321
    with temp_file(payload, binary=True) as zip_path, \
         temp_file(_appcast_with_enclosure("2.0.5", ed_signature="AbC123==", length=len(payload)),
                   suffix=".xml") as appcast_path:
        mod.APPCAST_FILE = appcast_path
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")) as download, \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(True, "verified")) as verify:
            mod.check_appcast_signature("2.0.5")

    download.assert_called_once()
    verify.assert_called_once_with(zip_path, "AbC123==")
    assert mod.passed == 2 and mod.failed == 0 and mod.skipped == 0


def test_appcast_signature_missing_fails():
    mod = load_module()
    payload = b"x" * 100
    with temp_file(payload, binary=True) as zip_path, \
         temp_file(_appcast_with_enclosure("2.0.5", ed_signature=None, length=len(payload)),
                   suffix=".xml") as appcast_path:
        mod.APPCAST_FILE = appcast_path
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature") as verify:
            mod.check_appcast_signature("2.0.5")

    assert not verify.called
    assert mod.failed == 1 and mod.passed == 1  # length ok, signature missing


def test_appcast_length_mismatch_fails():
    mod = load_module()
    payload = b"x" * 100
    with temp_file(payload, binary=True) as zip_path, \
         temp_file(_appcast_with_enclosure("2.0.5", ed_signature="sig==", length=999),
                   suffix=".xml") as appcast_path:
        mod.APPCAST_FILE = appcast_path
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(True, "verified")):
            mod.check_appcast_signature("2.0.5")
    assert mod.failed == 1 and mod.passed == 1  # signature verifies, length wrong


def test_appcast_signature_verification_failure():
    mod = load_module()
    payload = b"x" * 100
    with temp_file(payload, binary=True) as zip_path, \
         temp_file(_appcast_with_enclosure("2.0.5", ed_signature="bad==", length=len(payload)),
                   suffix=".xml") as appcast_path:
        mod.APPCAST_FILE = appcast_path
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(False, "bad signature")):
            mod.check_appcast_signature("2.0.5")
    assert mod.failed == 1 and mod.passed == 1  # signature fails, length ok


def test_appcast_no_item_for_version_fails_both():
    mod = load_module()
    payload = b"x" * 100
    with temp_file(payload, binary=True) as zip_path, \
         temp_file(_appcast_with_enclosure("1.0.0", ed_signature="sig==", length=len(payload)),
                   suffix=".xml") as appcast_path:
        mod.APPCAST_FILE = appcast_path
        with mock.patch.object(mod, "_download_github_release_asset") as download:
            mod.check_appcast_signature("2.0.5")
    assert not download.called
    assert mod.failed == 2


def test_appcast_signature_fails_when_uploaded_zip_unavailable():
    mod = load_module()
    with temp_file(_appcast_with_enclosure("2.0.5", ed_signature="sig==", length=10),
                   suffix=".xml") as appcast_path:
        mod.APPCAST_FILE = appcast_path
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=("", "could not download")):
            mod.check_appcast_signature("2.0.5")
    assert mod.failed == 2 and mod.passed == 0 and mod.skipped == 0


def test_appcast_signature_skips_when_appcast_absent():
    mod = load_module()
    mod.APPCAST_FILE = "/nonexistent/appcast.xml"
    with mock.patch.object(mod, "_download_github_release_asset") as download:
        mod.check_appcast_signature("2.0.5")

    assert not download.called
    assert mod.skipped == 2 and mod.passed == 0 and mod.failed == 0


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
