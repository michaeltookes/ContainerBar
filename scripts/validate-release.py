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
import hashlib
import plistlib
import re
import shutil
import tempfile
import urllib.request
import xml.etree.ElementTree as ET

# ── Configuration ──────────────────────────────────────────────────────────────
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_NAME = "ContainerBar"
INFO_PLIST = os.path.join(PROJECT_ROOT, "Distribution", "Info.plist")
CHANGELOG = os.path.join(PROJECT_ROOT, "CHANGELOG.md")
APP_BUNDLE = os.path.join(PROJECT_ROOT, "dist", f"{APP_NAME}.app")
RELEASE_ZIP = os.path.join(PROJECT_ROOT, "dist", f"{APP_NAME}.zip")
RELEASE_DMG = os.path.join(PROJECT_ROOT, "dist", f"{APP_NAME}.dmg")
APPCAST_FILE = os.path.join(PROJECT_ROOT, "docs", "appcast.xml")
HOMEBREW_CASK = os.path.expanduser("~/Desktop/Current Projects/homebrew-tap/Casks/containerbar.rb")
GITHUB_REPO = "michaeltookes/ContainerBar"
APPCAST_URL = "https://michaeltookes.github.io/ContainerBar/appcast.xml"
REQUIRED_RESOURCE_BUNDLES = (
    "ContainerBar_ContainerBar.bundle",
    "KeyboardShortcuts_KeyboardShortcuts.bundle",
)
BROKEN_SWIFTPM_RELEASE_PATHS = (
    b".build/arm64-apple-macosx/release",
    b".build/arm64e-apple-macosx/release",
    b".build/x86_64-apple-macosx/release",
)
# ───────────────────────────────────────────────────────────────────────────────

passed = 0
failed = 0
skipped = 0


def check(label, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  [PASS] {label}{': ' + detail if detail else ''}")
    else:
        failed += 1
        print(f"  [FAIL] {label}{': ' + detail if detail else ''}")


def skip(label, detail=""):
    """Record a check that could not run because a release artifact is absent.

    A skip is neither a pass nor a fail: the suite stays runnable (and green)
    with no dist/ present, so these checks only exercise a real release build.
    """
    global skipped
    skipped += 1
    print(f"  [SKIP] {label}{': ' + detail if detail else ''}")


def sha256_of_file(path):
    """Return the hex SHA-256 digest of a file, streamed in chunks."""
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(cmd):
    """Run a command argv sequence without a shell, return (returncode, stdout)."""
    if isinstance(cmd, str):
        raise TypeError("run() expects an argv sequence, not a shell command string")
    result = subprocess.run(cmd, capture_output=True, text=True, shell=False)
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
    rc, tags = run(["git", "tag", "-l", tag])
    if rc != 0:
        tags = ""
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
    rc, _ = run(["gh", "release", "view", tag, "--repo", GITHUB_REPO])
    check("GitHub release exists", rc == 0, tag)

    if rc == 0:
        _, assets = run(
            ["gh", "release", "view", tag, "--repo", GITHUB_REPO, "--json", "assets", "-q", ".assets[].name"]
        )
        has_zip = "ContainerBar.zip" in assets
        check("Release asset ContainerBar.zip uploaded", has_zip)
    else:
        check("Release asset ContainerBar.zip uploaded", False, "release not found")


def check_appcast(version):
    """Fetch appcast and verify it contains the version."""
    try:
        req = urllib.request.Request(APPCAST_URL, headers={"User-Agent": "validate-release/1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = resp.read()

        root = ET.fromstring(data)
        namespaces = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
        sparkle_ns = namespaces["sparkle"]

        found = False
        # Check both child elements and enclosure attributes
        for item in root.findall(".//item"):
            svs_elem = item.find(f"{{{sparkle_ns}}}shortVersionString")
            if svs_elem is not None and svs_elem.text == version:
                found = True
                break
            for enclosure in item.findall("enclosure"):
                if enclosure.get(f"{{{sparkle_ns}}}shortVersionString") == version:
                    found = True
                    break

        check("Appcast contains version", found, f"v{version}")
    except Exception as e:
        check("Appcast contains version", False, str(e))


def check_notarization():
    """Verify the app bundle passes Gatekeeper."""
    if not os.path.isdir(APP_BUNDLE):
        check("App notarization valid", False, f"app not found: {APP_BUNDLE}")
        return

    # spctl outputs to stderr
    result = subprocess.run(
        ["spctl", "--assess", "--verbose=2", APP_BUNDLE],
        capture_output=True, text=True
    )
    combined = result.stdout + result.stderr
    accepted = "accepted" in combined.lower()
    check("App notarization valid", accepted, combined.strip() if not accepted else "accepted")


def check_codesign():
    """Verify the built app passes strict code signing validation."""
    if not os.path.isdir(APP_BUNDLE):
        check("App codesign valid", False, f"app not found: {APP_BUNDLE}")
        return

    codesign_bin = shutil.which("codesign")
    if not codesign_bin:
        check("App codesign valid", False, "codesign not found")
        return

    try:
        result = subprocess.run(
            [codesign_bin, "--verify", "--deep", "--strict", "--verbose=2", APP_BUNDLE],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        check("App codesign valid", False, f"codesign execution failed: {exc}")
        return

    combined = (result.stdout + result.stderr).strip()
    check("App codesign valid", result.returncode == 0, combined if combined else "verified")


def check_framework_rpath():
    """Verify the app binary can resolve embedded frameworks from Contents/Frameworks."""
    binary = app_executable_path()
    sparkle_framework = os.path.join(APP_BUNDLE, "Contents", "Frameworks", "Sparkle.framework")

    if not os.path.isfile(binary):
        check("App framework rpath valid", False, f"binary not found: {binary}")
        return

    if not os.path.isdir(sparkle_framework):
        check("App framework rpath valid", False, f"framework not found: {sparkle_framework}")
        return

    otool_bin = shutil.which("otool")
    if not otool_bin:
        check("App framework rpath valid", False, "otool not found")
        return

    try:
        result = subprocess.run(
            [otool_bin, "-l", binary],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        check("App framework rpath valid", False, f"otool execution failed: {exc}")
        return

    if result.returncode != 0:
        combined = (result.stdout + result.stderr).strip()
        check("App framework rpath valid", False, combined if combined else "otool failed")
        return

    rpaths = []
    capture_path = False
    for line in result.stdout.splitlines():
        stripped = line.strip()
        if stripped == "cmd LC_RPATH":
            capture_path = True
            continue
        if capture_path and stripped.startswith("path "):
            rpaths.append(stripped.split(" ", 2)[1])
            capture_path = False

    check(
        "App framework rpath valid",
        "@executable_path/../Frameworks" in rpaths,
        ", ".join(rpaths) if rpaths else "no LC_RPATH entries found",
    )


def app_executable_path():
    """Return the packaged app executable path."""
    return os.path.join(APP_BUNDLE, "Contents", "MacOS", "ContainerBar")


def check_no_swiftpm_release_resource_path():
    """Verify the binary does not embed SwiftPM release resource fallback paths."""
    binary = app_executable_path()
    if not os.path.isfile(binary):
        check("No SwiftPM release resource path embedded", False, f"binary not found: {binary}")
        return
    with open(binary, "rb") as f:
        binary_contents = f.read()
    embedded_path = next(
        (path for path in BROKEN_SWIFTPM_RELEASE_PATHS if path in binary_contents),
        None,
    )
    check(
        "No SwiftPM release resource path embedded",
        embedded_path is None,
        (
            f"binary references {embedded_path.decode()}; SwiftPM resource accessor would crash on other Macs"
            if embedded_path
            else ""
        ),
    )


def check_required_resource_bundles():
    """Verify release-critical resource bundles are packaged inside the app."""
    resources_dir = os.path.join(APP_BUNDLE, "Contents", "Resources")
    missing = [
        name
        for name in REQUIRED_RESOURCE_BUNDLES
        if not os.path.isdir(os.path.join(resources_dir, name))
    ]
    check(
        "Required resource bundles packaged",
        not missing,
        ", ".join(missing) if missing else ", ".join(REQUIRED_RESOURCE_BUNDLES),
    )


def _extract_zip(zip_path, dest):
    """Extract a distributable zip into dest. Returns True on success."""
    rc, _ = run(["ditto", "-x", "-k", zip_path, dest])
    return rc == 0


def _attach_dmg(dmg_path, mountpoint):
    """Attach a DMG read-only at mountpoint without opening a Finder window."""
    rc, _ = run(
        ["hdiutil", "attach", dmg_path, "-nobrowse", "-readonly", "-mountpoint", mountpoint]
    )
    return rc == 0


def _detach_dmg(mountpoint):
    """Detach a mounted DMG; force so a lingering handle does not block us."""
    run(["hdiutil", "detach", mountpoint, "-force"])


def check_gatekeeper_zip():
    """Verify the app extracted from the distributable zip passes Gatekeeper.

    This is the artifact users actually download, so assess it as an execute
    target rather than trusting the loose dist/ bundle.
    """
    label = "Gatekeeper accepts zipped app"
    if not os.path.isfile(RELEASE_ZIP):
        skip(label, f"artifact absent: {RELEASE_ZIP}")
        return

    workdir = tempfile.mkdtemp(prefix="cb-gatekeeper-")
    try:
        if not _extract_zip(RELEASE_ZIP, workdir):
            check(label, False, f"could not extract {RELEASE_ZIP}")
            return
        app = os.path.join(workdir, f"{APP_NAME}.app")
        if not os.path.isdir(app):
            check(label, False, f"{APP_NAME}.app not found inside zip")
            return
        result = subprocess.run(
            ["spctl", "--assess", "--type", "execute", "--verbose=2", app],
            capture_output=True,
            text=True,
        )
        combined = (result.stdout + result.stderr).strip()
        accepted = "accepted" in combined.lower()
        check(label, accepted, "accepted" if accepted else combined)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def check_dmg_contents():
    """Verify dist/ContainerBar.dmg mounts and contains ContainerBar.app."""
    label = "DMG mounts and contains app"
    if not os.path.isfile(RELEASE_DMG):
        skip(label, f"artifact absent: {RELEASE_DMG}")
        return

    mountpoint = tempfile.mkdtemp(prefix="cb-dmg-")
    attached = False
    try:
        if not _attach_dmg(RELEASE_DMG, mountpoint):
            check(label, False, f"could not attach {RELEASE_DMG}")
            return
        attached = True
        app = os.path.join(mountpoint, f"{APP_NAME}.app")
        present = os.path.isdir(app)
        check(label, present, f"{APP_NAME}.app" if present else f"{APP_NAME}.app missing in DMG")
    finally:
        if attached:
            _detach_dmg(mountpoint)
        shutil.rmtree(mountpoint, ignore_errors=True)


def check_cask_sha256():
    """Verify the Homebrew cask sha256 matches the uploaded zip's sha256."""
    label = "Homebrew cask sha256 matches zip"
    if not os.path.isfile(RELEASE_ZIP):
        skip(label, f"artifact absent: {RELEASE_ZIP}")
        return
    if not os.path.isfile(HOMEBREW_CASK):
        skip(label, f"cask absent: {HOMEBREW_CASK}")
        return

    try:
        with open(HOMEBREW_CASK, "r") as f:
            content = f.read()
    except OSError as exc:
        check(label, False, f"could not read cask: {exc}")
        return

    match = re.search(r'sha256\s+"([0-9a-fA-F]{64})"', content)
    cask_sha = match.group(1).lower() if match else ""
    actual_sha = sha256_of_file(RELEASE_ZIP)
    matches = cask_sha == actual_sha
    check(
        label,
        matches,
        "matches" if matches else f"cask {cask_sha or '(none)'} != zip {actual_sha}",
    )


def check_cask_arm64():
    """Verify the Homebrew cask enforces Apple Silicon via depends_on arch: :arm64."""
    label = "Homebrew cask enforces arm64"
    if not os.path.isfile(HOMEBREW_CASK):
        skip(label, f"cask absent: {HOMEBREW_CASK}")
        return

    try:
        with open(HOMEBREW_CASK, "r") as f:
            content = f.read()
    except OSError as exc:
        check(label, False, f"could not read cask: {exc}")
        return

    found = re.search(r"depends_on\s+arch:\s*:arm64", content) is not None
    check(label, found, "depends_on arch: :arm64" if found else "missing depends_on arch: :arm64")


def _appcast_enclosure_for_version(root, version):
    """Return the <enclosure> element whose item matches version, or None."""
    sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    for item in root.findall(".//item"):
        svs_elem = item.find(f"{{{sparkle_ns}}}shortVersionString")
        item_matches = svs_elem is not None and svs_elem.text == version
        for enclosure in item.findall("enclosure"):
            if item_matches or enclosure.get(f"{{{sparkle_ns}}}shortVersionString") == version:
                return enclosure
    return None


def check_appcast_signature(version):
    """Verify the appcast entry has an edSignature and a length matching the zip.

    Reads the generated docs/appcast.xml against the local dist zip so the
    byte size is checked before the appcast is deployed.
    """
    sig_label = "Appcast edSignature present"
    len_label = "Appcast length matches zip size"
    if not os.path.isfile(RELEASE_ZIP):
        skip(sig_label, f"artifact absent: {RELEASE_ZIP}")
        skip(len_label, f"artifact absent: {RELEASE_ZIP}")
        return
    if not os.path.isfile(APPCAST_FILE):
        skip(sig_label, f"appcast absent: {APPCAST_FILE}")
        skip(len_label, f"appcast absent: {APPCAST_FILE}")
        return

    sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    try:
        root = ET.parse(APPCAST_FILE).getroot()
    except ET.ParseError as exc:
        check(sig_label, False, f"appcast parse error: {exc}")
        check(len_label, False, "appcast parse error")
        return

    enclosure = _appcast_enclosure_for_version(root, version)
    if enclosure is None:
        check(sig_label, False, f"no appcast item for v{version}")
        check(len_label, False, f"no appcast item for v{version}")
        return

    ed_signature = enclosure.get(f"{{{sparkle_ns}}}edSignature")
    check(sig_label, bool(ed_signature), "present" if ed_signature else "missing edSignature")

    zip_size = os.path.getsize(RELEASE_ZIP)
    length_attr = enclosure.get("length")
    try:
        length_matches = length_attr is not None and int(length_attr) == zip_size
    except ValueError:
        length_matches = False
    check(
        len_label,
        length_matches,
        f"{zip_size} bytes" if length_matches else f"appcast length {length_attr} != zip {zip_size}",
    )


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
    check_codesign()
    check_framework_rpath()
    check_required_resource_bundles()
    check_no_swiftpm_release_resource_path()
    check_notarization()
    check_gatekeeper_zip()
    check_dmg_contents()
    check_cask_sha256()
    check_cask_arm64()
    check_appcast_signature(version)

    total = passed + failed
    print(f"\n  {passed}/{total} checks passed.", end="")
    if skipped:
        print(f" {skipped} skipped (artifact absent).", end="")
    if failed == 0:
        print(" Release is complete.\n")
    else:
        print(f" {failed} check(s) failed — review above.\n")

    sys.exit(1 if failed > 0 else 0)


if __name__ == "__main__":
    main()
