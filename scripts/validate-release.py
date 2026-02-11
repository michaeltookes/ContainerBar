#!/usr/bin/env python3
"""
Post-release validation for ContainerBar.
Verifies all release artifacts are consistent and deployed correctly.

Usage: python3 scripts/validate-release.py <VERSION>
Example: python3 scripts/validate-release.py 1.2.0
"""

import subprocess
import sys
import os
import plistlib
import re
import urllib.request
import xml.etree.ElementTree as ET

# ── Configuration ──────────────────────────────────────────────────────────────
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INFO_PLIST = os.path.join(PROJECT_ROOT, "Distribution", "Info.plist")
CHANGELOG = os.path.join(PROJECT_ROOT, "CHANGELOG.md")
APP_BUNDLE = os.path.join(PROJECT_ROOT, "dist", "ContainerBar.app")
HOMEBREW_CASK = os.path.expanduser("~/Desktop/homebrew-tap/Casks/containerbar.rb")
GITHUB_REPO = "michaeltookes/ContainerBar"
APPCAST_URL = "https://michaeltookes.github.io/ContainerBar/appcast.xml"
# ───────────────────────────────────────────────────────────────────────────────

passed = 0
failed = 0


def check(label, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  [PASS] {label}{': ' + detail if detail else ''}")
    else:
        failed += 1
        print(f"  [FAIL] {label}{': ' + detail if detail else ''}")


def run(cmd):
    """Run a shell command, return (returncode, stdout)."""
    result = subprocess.run(cmd, capture_output=True, text=True, shell=isinstance(cmd, str))
    return result.returncode, result.stdout.strip()


def check_info_plist(version):
    """Verify Info.plist version and build number."""
    try:
        with open(INFO_PLIST, "rb") as f:
            plist = plistlib.load(f)
        plist_version = plist.get("CFBundleShortVersionString", "")
        build_number = plist.get("CFBundleVersion", "")
        check("Info.plist version", plist_version == version, plist_version)
        check("Info.plist build", build_number != "", build_number)
    except Exception as e:
        check("Info.plist version", False, str(e))
        check("Info.plist build", False, "could not read")


def check_changelog(version):
    """Verify CHANGELOG.md contains an entry for this version."""
    try:
        with open(CHANGELOG, "r") as f:
            content = f.read()
        pattern = rf"## \[{re.escape(version)}\]"
        found = bool(re.search(pattern, content))
        check("CHANGELOG.md entry found", found)
    except Exception as e:
        check("CHANGELOG.md entry found", False, str(e))


def check_git_tag(version):
    """Verify git tag exists locally."""
    tag = f"v{version}"
    rc, _ = run(f"git tag -l {tag}")
    _, tags = run(f"git tag -l {tag}")
    check("Git tag exists", tag in tags.split("\n"), tag)


def check_homebrew_cask(version):
    """Verify Homebrew cask has the correct version."""
    try:
        with open(HOMEBREW_CASK, "r") as f:
            content = f.read()
        match = re.search(r'version\s+"([^"]+)"', content)
        cask_version = match.group(1) if match else ""
        check("Homebrew cask version", cask_version == version, cask_version)
    except FileNotFoundError:
        check("Homebrew cask version", False, f"file not found: {HOMEBREW_CASK}")
    except Exception as e:
        check("Homebrew cask version", False, str(e))


def check_github_release(version):
    """Verify GitHub release exists and has the zip asset."""
    tag = f"v{version}"
    rc, output = run(f"gh release view {tag} --repo {GITHUB_REPO}")
    check("GitHub release exists", rc == 0, tag)

    if rc == 0:
        rc2, assets = run(f"gh release view {tag} --repo {GITHUB_REPO} --json assets -q '.assets[].name'")
        has_zip = "ContainerBar.zip" in assets
        check("Release asset ContainerBar.zip uploaded", has_zip)
    else:
        check("Release asset ContainerBar.zip uploaded", False, "release not found")


def check_appcast(version):
    """Fetch appcast and verify it contains the version."""
    try:
        req = urllib.request.Request(APPCAST_URL, headers={"User-Agent": "validate-release/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read().decode("utf-8")

        # Sparkle uses sparkle:shortVersionString attribute in enclosure elements
        found = version in data
        check("Appcast contains version", found, f"v{version}")
    except Exception as e:
        check("Appcast contains version", False, str(e))


def check_notarization():
    """Verify the app bundle passes Gatekeeper."""
    if not os.path.isdir(APP_BUNDLE):
        check("App notarization valid", False, f"app not found: {APP_BUNDLE}")
        return

    rc, output = run(f'spctl --assess --verbose=2 "{APP_BUNDLE}"')
    # spctl outputs to stderr
    result = subprocess.run(
        ["spctl", "--assess", "--verbose=2", APP_BUNDLE],
        capture_output=True, text=True
    )
    combined = result.stdout + result.stderr
    accepted = "accepted" in combined.lower()
    check("App notarization valid", accepted, combined.strip() if not accepted else "accepted")


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <VERSION>")
        print(f"Example: {sys.argv[0]} 1.2.0")
        sys.exit(2)

    version = sys.argv[1]

    print(f"\n  Release Validation: v{version}")
    print(f"  {'=' * 30}")

    check_info_plist(version)
    check_changelog(version)
    check_git_tag(version)
    check_homebrew_cask(version)
    check_github_release(version)
    check_appcast(version)
    check_notarization()

    total = passed + failed
    print(f"\n  {passed}/{total} checks passed.", end="")
    if failed == 0:
        print(" Release is complete.\n")
    else:
        print(f" {failed} check(s) failed — review above.\n")

    sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    main()
