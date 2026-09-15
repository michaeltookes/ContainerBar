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


def _make_app_side_effect(app_name, version=None, build=None):
    """Return a side_effect that mimics extract/attach by creating <name>.app."""
    def _side_effect(_src, dest):
        app = os.path.join(dest, f"{app_name}.app")
        os.makedirs(app, exist_ok=True)
        if version is not None or build is not None:
            contents_dir = os.path.join(app, "Contents")
            os.makedirs(contents_dir, exist_ok=True)
            plist = {}
            if version is not None:
                plist["CFBundleShortVersionString"] = version
            if build is not None:
                plist["CFBundleVersion"] = build
            with open(os.path.join(contents_dir, "Info.plist"), "wb") as handle:
                plistlib.dump(plist, handle)
        return True
    return _side_effect


@contextmanager
def expected_info_build(mod, build="7"):
    """Patch the expected Distribution/Info.plist build number."""
    with mock.patch.object(mod, "expected_info_plist_build_number", return_value=(build, "")):
        yield


@contextmanager
def uploaded_zip_packaging_passes(mod):
    """Patch uploaded-zip packaging helpers so focused tests stay readable."""
    def pass_check(_app_path, label):
        mod.check(label, True)

    with mock.patch.object(mod, "_check_framework_rpath", side_effect=pass_check) as rpath, \
         mock.patch.object(mod, "_check_required_resource_bundles", side_effect=pass_check) as resources, \
         mock.patch.object(mod, "_check_no_swiftpm_release_resource_path",
                           side_effect=pass_check) as swiftpm, \
         mock.patch.object(mod, "_check_executable_architecture", side_effect=pass_check) as arch:
        yield rpath, resources, swiftpm, arch


@contextmanager
def uploaded_zip_staple_passes(mod):
    """Patch uploaded-ZIP app stapler validation for focused tests."""
    with mock.patch.object(mod, "_stapler_valid", return_value=(True, "valid")) as stapler:
        yield stapler


@contextmanager
def uploaded_app_signing_passes(mod):
    """Patch production signing identity checks for focused artifact tests."""
    with mock.patch.object(mod, "_production_signing_identity_valid",
                           return_value=(True, "production identity")) as signing:
        yield signing


@contextmanager
def uploaded_dmg_container_passes(mod):
    """Patch uploaded-DMG container notarization checks for focused tests."""
    with mock.patch.object(mod, "_codesign_valid_container",
                           return_value=(True, "verified")) as codesign, \
         mock.patch.object(mod, "_stapler_valid",
                           return_value=(True, "valid")) as stapler:
        yield codesign, stapler


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


# ── codesign metadata ────────────────────────────────────────────────────────

@contextmanager
def production_signing_inputs(
    mod,
    expected_bundle_id="com.tookes.ContainerBar",
    app_bundle_id="com.tookes.ContainerBar",
    requirement_bundle_id="com.tookes.ContainerBar",
    team=None,
    authority=None,
):
    """Patch production signing inputs while preserving the validation logic."""
    team = mod.PRODUCTION_TEAM_ID if team is None else team
    authority = mod.PRODUCTION_SIGNING_AUTHORITY if authority is None else authority
    metadata = {
        "TeamIdentifier": team,
        "Authority": [
            authority,
            "Developer ID Certification Authority",
        ],
    }
    requirement = 'designated => anchor apple generic and identifier "{}"'.format(
        requirement_bundle_id
    )
    with mock.patch.object(mod, "expected_bundle_identifier",
                           return_value=(expected_bundle_id, "")), \
         mock.patch.object(mod, "_app_bundle_identifier",
                           return_value=(app_bundle_id, "")), \
         mock.patch.object(mod, "_codesign_metadata",
                           return_value=(metadata, "")), \
         mock.patch.object(mod, "_codesign_designated_requirement",
                           return_value=(requirement, requirement)):
        yield


def test_production_signing_identity_accepts_release_team_and_authority():
    mod = load_module()
    with production_signing_inputs(mod):
        ok, detail = mod._production_signing_identity_valid("/tmp/ContainerBar.app")

    assert ok
    assert mod.PRODUCTION_TEAM_ID in detail
    assert 'identifier "com.tookes.ContainerBar"' in detail


def test_production_signing_identity_rejects_wrong_bundle_identifier():
    mod = load_module()
    with production_signing_inputs(mod, app_bundle_id="com.example.OtherApp"):
        ok, detail = mod._production_signing_identity_valid("/tmp/ContainerBar.app")

    assert not ok
    assert "com.example.OtherApp" in detail


def test_production_signing_identity_rejects_wrong_designated_requirement():
    mod = load_module()
    with production_signing_inputs(mod, requirement_bundle_id="com.example.OtherApp"):
        ok, detail = mod._production_signing_identity_valid("/tmp/ContainerBar.app")

    assert not ok
    assert 'identifier "com.tookes.ContainerBar"' in detail


def test_production_signing_identity_rejects_wrong_team():
    mod = load_module()
    with production_signing_inputs(mod, team="ABCDE12345"):
        ok, detail = mod._production_signing_identity_valid("/tmp/ContainerBar.app")

    assert not ok
    assert "ABCDE12345" in detail


def test_production_signing_identity_rejects_wrong_authority():
    mod = load_module()
    with production_signing_inputs(
        mod,
        authority="Developer ID Application: Someone Else (ABCDE12345)",
    ):
        ok, detail = mod._production_signing_identity_valid("/tmp/ContainerBar.app")

    assert not ok
    assert "Someone Else" in detail


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
    cask = (
        'cask "containerbar" do\n'
        '  version "1.2.0"\n'
        '  url "https://github.com/michaeltookes/ContainerBar/releases/download/v#{version}/ContainerBar.zip"\n'
        "end\n"
    )
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")):
        mod.check_homebrew_cask("1.2.0")
    assert mod.passed == 2 and mod.failed == 0


def test_homebrew_cask_version_mismatch():
    mod = load_module()
    cask = (
        '  version "0.9.0"\n'
        '  url "https://github.com/michaeltookes/ContainerBar/releases/download/v#{version}/ContainerBar.zip"\n'
    )
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")):
        mod.check_homebrew_cask("1.2.0")
    assert mod.failed == 2


def test_homebrew_cask_fetch_failure():
    mod = load_module()
    with mock.patch.object(mod, "published_homebrew_cask", return_value=("", "not found")):
        mod.check_homebrew_cask("1.2.0")
    assert mod.failed == 2


def test_homebrew_cask_url_mismatch_fails():
    mod = load_module()
    cask = (
        '  version "2.0.4"\n'
        '  url "https://github.com/michaeltookes/ContainerBar/releases/download/v2.0.3/ContainerBar.zip"\n'
    )
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")):
        mod.check_homebrew_cask("2.0.4")
    assert mod.passed == 1 and mod.failed == 1


def test_homebrew_cask_url_ignores_commented_directive():
    mod = load_module()
    expected = "https://github.com/michaeltookes/ContainerBar/releases/download/v2.0.4/ContainerBar.zip"
    cask = (
        '  version "2.0.4"\n'
        f'  # url "{expected}"\n'
        '  url "https://github.com/michaeltookes/ContainerBar/releases/download/v2.0.3/ContainerBar.zip"\n'
    )
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")):
        mod.check_homebrew_cask("2.0.4")
    assert mod.passed == 1 and mod.failed == 1


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

def test_gatekeeper_zip_fails_when_uploaded_asset_unavailable():
    mod = load_module()
    with mock.patch.object(mod, "_download_github_release_asset",
                           return_value=("", "could not download")) as download, \
         mock.patch.object(mod, "_extract_zip") as extract:
        mod.check_gatekeeper_zip("2.0.4")

    download.assert_called_once()
    assert download.call_args[0][0:2] == ("v2.0.4", mod.RELEASE_ZIP_ASSET)
    assert not extract.called
    assert mod.failed == 9 and mod.passed == 0 and mod.skipped == 0


def test_gatekeeper_uploaded_zip_accepted():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")) as download, \
             mock.patch.object(mod, "_extract_zip",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")) as extract, \
             mock.patch.object(mod, "_gatekeeper_accepts_app",
                               return_value=(True, "accepted")) as gatekeeper, \
             uploaded_zip_staple_passes(mod) as stapler, \
             uploaded_app_signing_passes(mod) as signing, \
             uploaded_zip_packaging_passes(mod) as packaging_checks, \
             expected_info_build(mod, "7"):
            mod.check_gatekeeper_zip("2.0.4")

    download.assert_called_once()
    assert extract.called
    assert gatekeeper.called
    assert stapler.called
    assert signing.called
    assert stapler.call_args[0][0].endswith(
        os.path.join("extracted", f"{mod.APP_NAME}.app")
    )
    assert signing.call_args[0][0].endswith(
        os.path.join("extracted", f"{mod.APP_NAME}.app")
    )
    for packaging_check in packaging_checks:
        assert packaging_check.called
        checked_app = packaging_check.call_args[0][0]
        assert checked_app.endswith(os.path.join("extracted", f"{mod.APP_NAME}.app"))
        assert checked_app != mod.APP_BUNDLE
    assert mod.passed == 9 and mod.failed == 0 and mod.skipped == 0


def test_gatekeeper_uploaded_zip_stale_app_version_fails():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "_extract_zip",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.3", "7")), \
             mock.patch.object(mod, "_gatekeeper_accepts_app",
                               return_value=(True, "accepted")) as gatekeeper, \
             uploaded_zip_staple_passes(mod), \
             uploaded_app_signing_passes(mod), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_gatekeeper_zip("2.0.4")

    assert gatekeeper.called
    assert mod.passed == 8 and mod.failed == 1 and mod.skipped == 0


def test_gatekeeper_uploaded_zip_stale_app_build_fails():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "_extract_zip",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "6")), \
             mock.patch.object(mod, "_gatekeeper_accepts_app",
                               return_value=(True, "accepted")), \
             uploaded_zip_staple_passes(mod), \
             uploaded_app_signing_passes(mod), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_gatekeeper_zip("2.0.4")

    assert mod.passed == 8 and mod.failed == 1 and mod.skipped == 0


def test_gatekeeper_uploaded_zip_rejected():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "_extract_zip",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")), \
             mock.patch.object(mod, "_gatekeeper_accepts_app",
                               return_value=(False, "rejected")), \
             uploaded_zip_staple_passes(mod), \
             uploaded_app_signing_passes(mod), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_gatekeeper_zip("2.0.4")
    assert mod.failed == 1 and mod.passed == 8


def test_gatekeeper_uploaded_zip_unstapled_app_fails():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "_extract_zip",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")), \
             mock.patch.object(mod, "_gatekeeper_accepts_app",
                               return_value=(True, "accepted")), \
             mock.patch.object(mod, "_stapler_valid", return_value=(False, "not stapled")) as stapler, \
             uploaded_app_signing_passes(mod), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_gatekeeper_zip("2.0.4")

    assert stapler.called
    assert mod.failed == 1 and mod.passed == 8


def test_gatekeeper_uploaded_zip_wrong_signing_identity_fails():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "_extract_zip",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")), \
             mock.patch.object(mod, "_gatekeeper_accepts_app",
                               return_value=(True, "accepted")), \
             uploaded_zip_staple_passes(mod), \
             mock.patch.object(mod, "_production_signing_identity_valid",
                               return_value=(False, "wrong team")) as signing, \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_gatekeeper_zip("2.0.4")

    assert signing.called
    assert mod.failed == 1 and mod.passed == 8


def test_gatekeeper_uploaded_zip_extract_failure_fails():
    mod = load_module()
    with temp_file(b"zip", binary=True) as zip_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "_extract_zip", return_value=False):
            mod.check_gatekeeper_zip("2.0.4")
    assert mod.failed == 9


def test_executable_architecture_passes_for_arm64():
    mod = load_module()
    with tempfile.TemporaryDirectory() as tmp:
        app = os.path.join(tmp, f"{mod.APP_NAME}.app")
        macos_dir = os.path.join(app, "Contents", "MacOS")
        os.makedirs(macos_dir)
        binary = os.path.join(macos_dir, mod.APP_NAME)
        with open(binary, "wb") as handle:
            handle.write(b"mach-o")

        with mock.patch.object(mod.shutil, "which", return_value="/usr/bin/lipo"), \
             mock.patch.object(mod.subprocess, "run",
                               return_value=fake_completed(stdout="arm64\n")) as run:
            mod._check_executable_architecture(app, "Uploaded ZIP executable is arm64-only")

    run.assert_called_once()
    assert run.call_args[0][0] == ["/usr/bin/lipo", "-archs", binary]
    assert mod.passed == 1 and mod.failed == 0


def test_executable_architecture_fails_for_x86_only():
    mod = load_module()
    with tempfile.TemporaryDirectory() as tmp:
        app = os.path.join(tmp, f"{mod.APP_NAME}.app")
        macos_dir = os.path.join(app, "Contents", "MacOS")
        os.makedirs(macos_dir)
        with open(os.path.join(macos_dir, mod.APP_NAME), "wb") as handle:
            handle.write(b"mach-o")

        with mock.patch.object(mod.shutil, "which", return_value="/usr/bin/lipo"), \
             mock.patch.object(mod.subprocess, "run",
                               return_value=fake_completed(stdout="x86_64\n")):
            mod._check_executable_architecture(app, "Uploaded ZIP executable is arm64-only")

    assert mod.failed == 1 and mod.passed == 0


def test_executable_architecture_fails_for_universal_binary():
    mod = load_module()
    with tempfile.TemporaryDirectory() as tmp:
        app = os.path.join(tmp, f"{mod.APP_NAME}.app")
        macos_dir = os.path.join(app, "Contents", "MacOS")
        os.makedirs(macos_dir)
        with open(os.path.join(macos_dir, mod.APP_NAME), "wb") as handle:
            handle.write(b"mach-o")

        with mock.patch.object(mod.shutil, "which", return_value="/usr/bin/lipo"), \
             mock.patch.object(mod.subprocess, "run",
                               return_value=fake_completed(stdout="arm64 x86_64\n")):
            mod._check_executable_architecture(app, "Uploaded ZIP executable is arm64-only")

    assert mod.failed == 1 and mod.passed == 0


# ── check_dmg_contents ──────────────────────────────────────────────────────

def test_dmg_fails_when_uploaded_asset_unavailable():
    mod = load_module()
    with mock.patch.object(mod, "_download_github_release_asset",
                           return_value=("", "could not download")) as download, \
         mock.patch.object(mod, "_attach_dmg") as attach:
        mod.check_dmg_contents("2.0.4")

    download.assert_called_once()
    assert download.call_args[0][0:2] == ("v2.0.4", mod.RELEASE_DMG_ASSET)
    assert not attach.called
    assert mod.failed == 12 and mod.passed == 0 and mod.skipped == 0


def test_dmg_contains_valid_current_version_app():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")) as download, \
             mock.patch.object(mod, "_attach_dmg",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")) as attach, \
             mock.patch.object(mod, "_detach_dmg") as detach, \
             mock.patch.object(mod, "_codesign_valid", return_value=(True, "verified")) as codesign, \
             mock.patch.object(mod, "_gatekeeper_accepts_app",
                               return_value=(True, "accepted")) as gatekeeper, \
             uploaded_dmg_container_passes(mod) as container_checks, \
             uploaded_app_signing_passes(mod) as signing, \
             uploaded_zip_packaging_passes(mod) as packaging_checks, \
             expected_info_build(mod, "7"):
            mod.check_dmg_contents("2.0.4")
            download.assert_called_once()
            assert attach.call_args[0][0] == dmg_path
            assert detach.called, "a mounted DMG must always be detached"
            assert codesign.called
            assert signing.called
            assert gatekeeper.called
            for container_check in container_checks:
                assert container_check.called
                assert container_check.call_args[0][0] == dmg_path
            for packaging_check in packaging_checks:
                assert packaging_check.called
                checked_app = packaging_check.call_args[0][0]
                assert checked_app.endswith(f"{mod.APP_NAME}.app")
                assert checked_app != mod.APP_BUNDLE
    assert mod.passed == 12 and mod.failed == 0 and mod.skipped == 0


def test_dmg_stale_app_version_fails():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")), \
             mock.patch.object(mod, "_attach_dmg",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.3", "7")), \
             mock.patch.object(mod, "_detach_dmg"), \
             mock.patch.object(mod, "_codesign_valid", return_value=(True, "verified")), \
             mock.patch.object(mod, "_gatekeeper_accepts_app", return_value=(True, "accepted")), \
             uploaded_dmg_container_passes(mod), \
             uploaded_app_signing_passes(mod), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_dmg_contents("2.0.4")

    assert mod.passed == 11 and mod.failed == 1


def test_dmg_stale_app_build_fails():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")), \
             mock.patch.object(mod, "_attach_dmg",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "6")), \
             mock.patch.object(mod, "_detach_dmg"), \
             mock.patch.object(mod, "_codesign_valid", return_value=(True, "verified")), \
             mock.patch.object(mod, "_gatekeeper_accepts_app", return_value=(True, "accepted")), \
             uploaded_dmg_container_passes(mod), \
             uploaded_app_signing_passes(mod), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_dmg_contents("2.0.4")

    assert mod.passed == 11 and mod.failed == 1


def test_dmg_missing_app_fails():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        # attaches successfully but the mountpoint has no .app
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")), \
             mock.patch.object(mod, "_attach_dmg", return_value=True), \
             mock.patch.object(mod, "_detach_dmg") as detach, \
             uploaded_dmg_container_passes(mod):
            mod.check_dmg_contents("2.0.4")
            assert detach.called
    assert mod.passed == 2 and mod.failed == 10


def test_dmg_attach_failure_does_not_detach():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")), \
             mock.patch.object(mod, "_attach_dmg", return_value=False), \
             mock.patch.object(mod, "_detach_dmg") as detach, \
             uploaded_dmg_container_passes(mod):
            mod.check_dmg_contents("2.0.4")
            assert not detach.called, "no attach means nothing to detach"
    assert mod.passed == 2 and mod.failed == 10


def test_dmg_codesign_failure_fails_bundle_validation():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")), \
             mock.patch.object(mod, "_attach_dmg",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")), \
             mock.patch.object(mod, "_detach_dmg"), \
             mock.patch.object(mod, "_codesign_valid", return_value=(False, "bad signature")), \
             mock.patch.object(mod, "_gatekeeper_accepts_app", return_value=(True, "accepted")), \
             uploaded_dmg_container_passes(mod), \
             uploaded_app_signing_passes(mod), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_dmg_contents("2.0.4")

    assert mod.passed == 11 and mod.failed == 1


def test_dmg_gatekeeper_failure_fails_bundle_validation():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")), \
             mock.patch.object(mod, "_attach_dmg",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")), \
             mock.patch.object(mod, "_detach_dmg"), \
             mock.patch.object(mod, "_codesign_valid", return_value=(True, "verified")), \
             mock.patch.object(mod, "_gatekeeper_accepts_app", return_value=(False, "rejected")), \
             uploaded_dmg_container_passes(mod), \
             uploaded_app_signing_passes(mod), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_dmg_contents("2.0.4")

    assert mod.passed == 11 and mod.failed == 1


def test_dmg_wrong_signing_identity_fails_bundle_validation():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")), \
             mock.patch.object(mod, "_attach_dmg",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")), \
             mock.patch.object(mod, "_detach_dmg"), \
             mock.patch.object(mod, "_codesign_valid", return_value=(True, "verified")), \
             mock.patch.object(mod, "_production_signing_identity_valid",
                               return_value=(False, "wrong team")) as signing, \
             mock.patch.object(mod, "_gatekeeper_accepts_app", return_value=(True, "accepted")), \
             uploaded_dmg_container_passes(mod), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_dmg_contents("2.0.4")

    assert signing.called
    assert mod.passed == 11 and mod.failed == 1


def test_dmg_container_codesign_failure_fails_validation():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")), \
             mock.patch.object(mod, "_codesign_valid_container",
                               return_value=(False, "bad dmg signature")), \
             mock.patch.object(mod, "_stapler_valid", return_value=(True, "valid")), \
             mock.patch.object(mod, "_attach_dmg",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")), \
             mock.patch.object(mod, "_detach_dmg"), \
             mock.patch.object(mod, "_codesign_valid", return_value=(True, "verified")), \
             uploaded_app_signing_passes(mod), \
             mock.patch.object(mod, "_gatekeeper_accepts_app", return_value=(True, "accepted")), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_dmg_contents("2.0.4")

    assert mod.passed == 11 and mod.failed == 1


def test_dmg_container_stapler_failure_fails_validation():
    mod = load_module()
    with temp_file(b"dmg", binary=True) as dmg_path:
        with mock.patch.object(mod, "_download_github_release_asset",
                               return_value=(dmg_path, "")), \
             mock.patch.object(mod, "_codesign_valid_container", return_value=(True, "verified")), \
             mock.patch.object(mod, "_stapler_valid", return_value=(False, "not stapled")), \
             mock.patch.object(mod, "_attach_dmg",
                               side_effect=_make_app_side_effect(mod.APP_NAME, "2.0.4", "7")), \
             mock.patch.object(mod, "_detach_dmg"), \
             mock.patch.object(mod, "_codesign_valid", return_value=(True, "verified")), \
             uploaded_app_signing_passes(mod), \
             mock.patch.object(mod, "_gatekeeper_accepts_app", return_value=(True, "accepted")), \
             uploaded_zip_packaging_passes(mod), \
             expected_info_build(mod, "7"):
            mod.check_dmg_contents("2.0.4")

    assert mod.passed == 11 and mod.failed == 1


# ── check_cask_sha256 ───────────────────────────────────────────────────────

def test_cask_sha256_matches_uploaded_release_asset():
    mod = load_module()
    digest = "c" * 64
    cask = f'cask "containerbar" do\n  sha256 "{digest}"\nend\n'
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")) as published, \
         mock.patch.object(mod, "github_release_asset_sha256",
                           return_value=(digest, "")) as asset_sha:
        mod.check_cask_sha256("2.0.4")

    published.assert_called_once()
    asset_sha.assert_called_once_with("2.0.4")
    assert mod.passed == 1 and mod.failed == 0


def test_cask_sha256_mismatch():
    mod = load_module()
    cask = '  sha256 "{}"\n'.format("0" * 64)
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")), \
         mock.patch.object(mod, "github_release_asset_sha256", return_value=("d" * 64, "")):
        mod.check_cask_sha256("2.0.4")
    assert mod.failed == 1


def test_cask_sha256_ignores_commented_digest():
    mod = load_module()
    uploaded_digest = "d" * 64
    stale_active_digest = "0" * 64
    cask = '# sha256 "{}"\n  sha256 "{}"\n'.format(uploaded_digest, stale_active_digest)
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")), \
         mock.patch.object(mod, "github_release_asset_sha256", return_value=(uploaded_digest, "")):
        mod.check_cask_sha256("2.0.4")
    assert mod.failed == 1 and mod.passed == 0


def test_cask_sha256_fails_when_release_asset_digest_unavailable():
    mod = load_module()
    cask = '  sha256 "{}"\n'.format("0" * 64)
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")), \
         mock.patch.object(mod, "github_release_asset_sha256",
                           return_value=("", "asset digest unavailable")):
        mod.check_cask_sha256("2.0.4")
    assert mod.failed == 1 and mod.passed == 0 and mod.skipped == 0


def test_cask_sha256_fails_when_published_cask_unavailable():
    mod = load_module()
    with mock.patch.object(mod, "published_homebrew_cask", return_value=("", "not found")), \
         mock.patch.object(mod, "github_release_asset_sha256") as asset_sha:
        mod.check_cask_sha256("2.0.4")

    assert not asset_sha.called
    assert mod.failed == 1 and mod.passed == 0 and mod.skipped == 0


# ── check_cask_arm64 ────────────────────────────────────────────────────────

def test_cask_arm64_present():
    mod = load_module()
    cask = 'cask "containerbar" do\n  depends_on arch: :arm64\nend\n'
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")):
        mod.check_cask_arm64()
    assert mod.passed == 1 and mod.failed == 0


def test_cask_arm64_missing_fails():
    mod = load_module()
    cask = 'cask "containerbar" do\n  version "2.0.4"\nend\n'
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")):
        mod.check_cask_arm64()
    assert mod.failed == 1


def test_cask_arm64_ignores_commented_directive():
    mod = load_module()
    cask = 'cask "containerbar" do\n  # depends_on arch: :arm64\nend\n'
    with mock.patch.object(mod, "published_homebrew_cask", return_value=(cask, "")):
        mod.check_cask_arm64()
    assert mod.failed == 1 and mod.passed == 0


def test_cask_arm64_fails_when_published_cask_unavailable():
    mod = load_module()
    with mock.patch.object(mod, "published_homebrew_cask", return_value=("", "not found")):
        mod.check_cask_arm64()
    assert mod.failed == 1 and mod.passed == 0 and mod.skipped == 0


# ── check_appcast_signature ─────────────────────────────────────────────────

def _appcast_with_enclosure(
    version,
    ed_signature=None,
    length=None,
    url=None,
    build="7",
    build_attr=False,
    hardware="arm64",
):
    sig_attr = ' sparkle:edSignature="{}"'.format(ed_signature) if ed_signature is not None else ""
    len_attr = ' length="{}"'.format(length) if length is not None else ""
    build_element = "" if build is None or build_attr else "<sparkle:version>{}</sparkle:version>".format(build)
    build_attr_value = ' sparkle:version="{}"'.format(build) if build is not None and build_attr else ""
    hardware_element = (
        "" if hardware is None else "<sparkle:hardwareRequirements>{}</sparkle:hardwareRequirements>".format(hardware)
    )
    enclosure_url = url or (
        "https://github.com/michaeltookes/ContainerBar/releases/download/"
        "v{}/ContainerBar.zip".format(version)
    )
    return (
        '<?xml version="1.0"?>'
        '<rss xmlns:sparkle="{ns}"><channel><item>'
        "{build_element}"
        "<sparkle:shortVersionString>{v}</sparkle:shortVersionString>"
        "{hardware_element}"
        '<enclosure url="{url}"{sig}{ln}{build_attr}/>'
        "</item></channel></rss>"
    ).format(
        ns=SPARKLE_NS,
        v=version,
        url=enclosure_url,
        sig=sig_attr,
        ln=len_attr,
        build_element=build_element,
        build_attr=build_attr_value,
        hardware_element=hardware_element,
    )


def _appcast_root(mod, xml):
    return mod.ET.fromstring(xml)


def test_appcast_signature_and_length_ok():
    mod = load_module()
    payload = b"x" * 321
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure("2.0.5", ed_signature="AbC123==", length=len(payload)),
    )
    expected_url = mod.expected_appcast_enclosure_url("2.0.5")
    with temp_file(payload, binary=True) as zip_path:
        with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
             mock.patch.object(mod, "_download_url_to_file",
                               return_value=(zip_path, "")) as download, \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(True, "verified")) as verify, \
             expected_info_build(mod, "7"):
            mod.check_appcast_signature("2.0.5")

    download.assert_called_once()
    assert download.call_args[0][0] == expected_url
    verify.assert_called_once_with(zip_path, "AbC123==")
    assert mod.passed == 5 and mod.failed == 0 and mod.skipped == 0


def test_appcast_signature_missing_fails():
    mod = load_module()
    payload = b"x" * 100
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure("2.0.5", ed_signature=None, length=len(payload)),
    )
    with temp_file(payload, binary=True) as zip_path:
        with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
             mock.patch.object(mod, "_download_url_to_file",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature") as verify, \
             expected_info_build(mod, "7"):
            mod.check_appcast_signature("2.0.5")

    assert not verify.called
    assert mod.failed == 1 and mod.passed == 4  # URL + build + hardware + length ok


def test_appcast_length_mismatch_fails():
    mod = load_module()
    payload = b"x" * 100
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure("2.0.5", ed_signature="sig==", length=999),
    )
    with temp_file(payload, binary=True) as zip_path:
        with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
             mock.patch.object(mod, "_download_url_to_file",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(True, "verified")), \
             expected_info_build(mod, "7"):
            mod.check_appcast_signature("2.0.5")
    assert mod.failed == 1 and mod.passed == 4  # URL + build + hardware + signature ok


def test_appcast_signature_verification_failure():
    mod = load_module()
    payload = b"x" * 100
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure("2.0.5", ed_signature="bad==", length=len(payload)),
    )
    with temp_file(payload, binary=True) as zip_path:
        with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
             mock.patch.object(mod, "_download_url_to_file",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(False, "bad signature")), \
             expected_info_build(mod, "7"):
            mod.check_appcast_signature("2.0.5")
    assert mod.failed == 1 and mod.passed == 4  # URL + build + hardware + length ok


def test_appcast_build_mismatch_fails():
    mod = load_module()
    payload = b"x" * 100
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure("2.0.5", ed_signature="sig==", length=len(payload), build="6"),
    )
    with temp_file(payload, binary=True) as zip_path:
        with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
             mock.patch.object(mod, "_download_url_to_file",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(True, "verified")), \
             expected_info_build(mod, "7"):
            mod.check_appcast_signature("2.0.5")
    assert mod.failed == 1 and mod.passed == 4


def test_appcast_build_matches_enclosure_attribute():
    mod = load_module()
    payload = b"x" * 100
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure(
            "2.0.5",
            ed_signature="sig==",
            length=len(payload),
            build="7",
            build_attr=True,
        ),
    )
    with temp_file(payload, binary=True) as zip_path:
        with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
             mock.patch.object(mod, "_download_url_to_file",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(True, "verified")), \
             expected_info_build(mod, "7"):
            mod.check_appcast_signature("2.0.5")
    assert mod.failed == 0 and mod.passed == 5


def test_appcast_hardware_requirement_missing_fails():
    mod = load_module()
    payload = b"x" * 100
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure(
            "2.0.5",
            ed_signature="sig==",
            length=len(payload),
            hardware=None,
        ),
    )
    with temp_file(payload, binary=True) as zip_path:
        with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
             mock.patch.object(mod, "_download_url_to_file",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(True, "verified")), \
             expected_info_build(mod, "7"):
            mod.check_appcast_signature("2.0.5")

    assert mod.failed == 1 and mod.passed == 4


def test_appcast_hardware_requirement_mixed_architectures_fail():
    mod = load_module()
    payload = b"x" * 100
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure(
            "2.0.5",
            ed_signature="sig==",
            length=len(payload),
            hardware="x86_64,arm64",
        ),
    )
    with temp_file(payload, binary=True) as zip_path:
        with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
             mock.patch.object(mod, "_download_url_to_file",
                               return_value=(zip_path, "")), \
             mock.patch.object(mod, "verify_sparkle_update_signature",
                               return_value=(True, "verified")), \
             expected_info_build(mod, "7"):
            mod.check_appcast_signature("2.0.5")

    assert mod.failed == 1 and mod.passed == 4


def test_appcast_no_item_for_version_fails_both():
    mod = load_module()
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure("1.0.0", ed_signature="sig==", length=100),
    )
    with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
         mock.patch.object(mod, "_download_url_to_file") as download:
        mod.check_appcast_signature("2.0.5")
    assert not download.called
    assert mod.failed == 5


def test_appcast_signature_fails_when_enclosure_archive_unavailable():
    mod = load_module()
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure("2.0.5", ed_signature="sig==", length=10),
    )
    with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
         mock.patch.object(mod, "_download_url_to_file",
                           return_value=("", "could not download")), \
         expected_info_build(mod, "7"):
        mod.check_appcast_signature("2.0.5")
    assert mod.failed == 2 and mod.passed == 3 and mod.skipped == 0


def test_appcast_signature_fails_when_deployed_appcast_unavailable():
    mod = load_module()
    with mock.patch.object(mod, "fetch_appcast_root", return_value=(None, "not found")), \
         mock.patch.object(mod, "_download_url_to_file") as download:
        mod.check_appcast_signature("2.0.5")

    assert not download.called
    assert mod.failed == 5 and mod.passed == 0 and mod.skipped == 0


def test_appcast_signature_fails_when_enclosure_url_is_not_canonical():
    mod = load_module()
    appcast = _appcast_root(
        mod,
        _appcast_with_enclosure(
            "2.0.5",
            ed_signature="sig==",
            length=10,
            url="https://example.com/releases/v2.0.5/ContainerBar.zip",
        ),
    )
    with mock.patch.object(mod, "fetch_appcast_root", return_value=(appcast, "")), \
         mock.patch.object(mod, "_download_url_to_file") as download, \
         mock.patch.object(mod, "verify_sparkle_update_signature") as verify, \
         expected_info_build(mod, "7"):
        mod.check_appcast_signature("2.0.5")

    assert not download.called
    assert not verify.called
    assert mod.failed == 3 and mod.passed == 2 and mod.skipped == 0


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
