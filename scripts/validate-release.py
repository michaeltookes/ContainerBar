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
import json
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
RELEASE_ZIP_ASSET = f"{APP_NAME}.zip"
RELEASE_DMG_ASSET = f"{APP_NAME}.dmg"
RELEASE_ZIP = os.path.join(PROJECT_ROOT, "dist", RELEASE_ZIP_ASSET)
HOMEBREW_TAP_REPO = "michaeltookes/homebrew-tap"
HOMEBREW_CASK_PATH = "Casks/containerbar.rb"
HOMEBREW_CASK_URL = f"https://raw.githubusercontent.com/{HOMEBREW_TAP_REPO}/main/{HOMEBREW_CASK_PATH}"
GITHUB_REPO = "michaeltookes/ContainerBar"
APPCAST_URL = "https://michaeltookes.github.io/ContainerBar/appcast.xml"
SIGN_UPDATE_LOCATIONS = (
    os.path.join(
        PROJECT_ROOT,
        ".build",
        "xcode-release",
        "SourcePackages",
        "artifacts",
        "sparkle",
        "Sparkle",
        "bin",
        "sign_update",
    ),
    os.path.join(
        PROJECT_ROOT,
        ".build",
        "artifacts",
        "sparkle",
        "Sparkle",
        "bin",
        "sign_update",
    ),
    "/opt/homebrew/bin/sign_update",
    "/usr/local/bin/sign_update",
    os.path.join(os.path.expanduser("~"), "Library", "Developer", "Sparkle", "bin", "sign_update"),
)
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
_published_cask_cache = None


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


def _fetch_url_bytes(url, timeout=10):
    """Fetch URL bytes with the validator user agent."""
    req = urllib.request.Request(url, headers={"User-Agent": "validate-release/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def _download_url_to_file(url, dest):
    """Download a URL to dest, returning (path, detail)."""
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "validate-release/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp, open(dest, "wb") as handle:
            shutil.copyfileobj(resp, handle)
    except Exception as exc:
        return "", f"could not download {url}: {exc}"
    return dest, ""


def fetch_appcast_root():
    """Fetch and parse the deployed Sparkle appcast."""
    try:
        return ET.fromstring(_fetch_url_bytes(APPCAST_URL)), ""
    except ET.ParseError as exc:
        return None, f"appcast parse error: {exc}"
    except Exception as exc:
        return None, str(exc)


def published_homebrew_cask():
    """Return the published Homebrew tap cask content, not a local checkout."""
    global _published_cask_cache
    if _published_cask_cache is not None:
        return _published_cask_cache

    try:
        content = _fetch_url_bytes(HOMEBREW_CASK_URL, timeout=30).decode("utf-8")
        _published_cask_cache = content, ""
    except Exception as exc:
        _published_cask_cache = "", f"could not fetch published cask {HOMEBREW_CASK_URL}: {exc}"
    return _published_cask_cache


def _cask_has_active_arm64_dependency(content):
    """Return true only when the cask has an active arm64 dependency line."""
    return re.search(r"(?m)^\s*depends_on\s+arch:\s*:arm64\b", content) is not None


def _active_cask_sha256(content):
    """Return the active cask sha256 digest, ignoring commented-out lines."""
    match = re.search(r'(?m)^\s*sha256\s+"([0-9a-fA-F]{64})"', content)
    return match.group(1).lower() if match else ""


def _normalize_sha256_digest(value):
    """Return a lowercase SHA-256 hex digest from GitHub's digest format."""
    digest = value.strip()
    if digest.startswith("sha256:"):
        digest = digest[len("sha256:"):]
    digest = digest.lower()
    return digest if re.fullmatch(r"[0-9a-f]{64}", digest) else ""


def github_release_assets(version):
    """Return (release_found, assets, detail) for the tagged GitHub release."""
    tag = f"v{version}"
    rc, output = run(["gh", "release", "view", tag, "--repo", GITHUB_REPO, "--json", "assets"])
    if rc != 0:
        return False, [], f"release not found: {tag}"

    try:
        payload = json.loads(output)
    except json.JSONDecodeError as exc:
        return True, [], f"could not parse release assets: {exc}"

    assets = payload.get("assets")
    if not isinstance(assets, list):
        return True, [], "unexpected GitHub release assets payload"
    return True, assets, ""


def github_release_asset_sha256(version):
    """Return the SHA-256 of the uploaded release zip asset.

    Prefer GitHub's asset digest metadata, then fall back to downloading the
    tagged asset. The local dist zip may be stale, so it is deliberately not
    used for the Homebrew cask comparison.
    """
    tag = f"v{version}"
    rc, digest_output = run(
        [
            "gh",
            "release",
            "view",
            tag,
            "--repo",
            GITHUB_REPO,
            "--json",
            "assets",
            "-q",
            f'.assets[] | select(.name == "{RELEASE_ZIP_ASSET}") | .digest',
        ]
    )
    if rc == 0:
        digest = next(
            (line.strip() for line in digest_output.splitlines() if line.strip() and line.strip() != "null"),
            "",
        )
        if digest:
            normalized = _normalize_sha256_digest(digest)
            if normalized:
                return normalized, ""
            return "", f"invalid GitHub digest for {RELEASE_ZIP_ASSET}: {digest}"

    return _download_github_release_asset_sha256(tag)


def _download_github_release_asset(tag, asset_name, workdir):
    """Download a named GitHub release asset into workdir."""
    rc, _ = run(
        [
            "gh",
            "release",
            "download",
            tag,
            "--repo",
            GITHUB_REPO,
            "--pattern",
            asset_name,
            "--dir",
            workdir,
            "--clobber",
        ]
    )
    if rc != 0:
        return "", f"could not download {asset_name} from {tag}"

    asset_path = os.path.join(workdir, asset_name)
    if not os.path.isfile(asset_path):
        return "", f"{asset_name} missing after download from {tag}"

    return asset_path, ""


def _download_github_release_asset_sha256(tag):
    """Download the uploaded release zip and return its SHA-256 digest."""
    workdir = tempfile.mkdtemp(prefix="cb-release-asset-")
    try:
        asset_path, detail = _download_github_release_asset(tag, RELEASE_ZIP_ASSET, workdir)
        if not asset_path:
            return "", detail

        return sha256_of_file(asset_path), ""
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def sparkle_sign_update_path():
    """Return the Sparkle sign_update tool path, if available."""
    override = os.environ.get("SPARKLE_SIGN_UPDATE", "").strip()
    if override:
        return override if os.path.isfile(override) and os.access(override, os.X_OK) else ""

    for path in SIGN_UPDATE_LOCATIONS:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    return ""


def verify_sparkle_update_signature(update_path, ed_signature):
    """Verify a Sparkle EdDSA signature against an update archive."""
    sign_update = sparkle_sign_update_path()
    if not sign_update:
        return False, "Sparkle sign_update not found"

    rc, output = run([sign_update, "--verify", update_path, ed_signature])
    if rc == 0:
        return True, "verified"
    return False, output or "sign_update --verify failed"


def expected_appcast_enclosure_url(version):
    """Return the canonical GitHub release URL for the appcast zip enclosure."""
    return f"https://github.com/{GITHUB_REPO}/releases/download/v{version}/{RELEASE_ZIP_ASSET}"


def _app_bundle_short_version(app_path):
    """Return CFBundleShortVersionString from an app bundle."""
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    try:
        with open(plist_path, "rb") as handle:
            plist = plistlib.load(handle)
    except Exception as exc:
        return "", f"could not read {plist_path}: {exc}"

    version = plist.get("CFBundleShortVersionString", "")
    return version, "" if version else "CFBundleShortVersionString missing"


def _codesign_valid(app_path):
    """Return whether an app bundle passes strict codesign verification."""
    codesign_bin = shutil.which("codesign")
    if not codesign_bin:
        return False, "codesign not found"

    try:
        result = subprocess.run(
            [codesign_bin, "--verify", "--deep", "--strict", "--verbose=2", app_path],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        return False, f"codesign execution failed: {exc}"

    combined = (result.stdout + result.stderr).strip()
    return result.returncode == 0, combined if combined else "verified"


def _gatekeeper_accepts_app(app_path):
    """Return whether Gatekeeper accepts an app as an executable target."""
    try:
        result = subprocess.run(
            ["spctl", "--assess", "--type", "execute", "--verbose=2", app_path],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        return False, f"spctl execution failed: {exc}"

    combined = (result.stdout + result.stderr).strip()
    accepted = result.returncode == 0 and "accepted" in combined.lower()
    return accepted, "accepted" if accepted else combined or "spctl assessment failed"


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
    """Verify the published Homebrew cask has the correct version."""
    content, detail = published_homebrew_cask()
    if not content:
        check("Published Homebrew cask version", False, detail)
        return

    match = re.search(r'version\s+"([^"]+)"', content)
    cask_version = match.group(1) if match else ""
    check("Published Homebrew cask version", cask_version == version, cask_version)


def check_github_release(version):
    """Verify GitHub release exists and has the required assets."""
    tag = f"v{version}"
    release_found, assets, detail = github_release_assets(version)
    check("GitHub release exists", release_found, tag)

    if not release_found or detail:
        failure_detail = detail or "release not found"
        check(f"Release asset {RELEASE_ZIP_ASSET} uploaded", False, failure_detail)
        check(f"Release asset {RELEASE_DMG_ASSET} uploaded", False, failure_detail)
        return

    asset_names = {
        asset.get("name", "")
        for asset in assets
        if isinstance(asset, dict)
    }
    has_zip = RELEASE_ZIP_ASSET in asset_names
    has_dmg = RELEASE_DMG_ASSET in asset_names
    check(f"Release asset {RELEASE_ZIP_ASSET} uploaded", has_zip)
    check(f"Release asset {RELEASE_DMG_ASSET} uploaded", has_dmg)


def check_appcast(version):
    """Fetch appcast and verify it contains the version."""
    root, detail = fetch_appcast_root()
    if root is None:
        check("Appcast contains version", False, detail)
        return

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


def check_gatekeeper_zip(version):
    """Verify the app extracted from the uploaded release zip passes Gatekeeper.

    This is the artifact users actually download, so assess it as an execute
    target rather than trusting the loose dist/ bundle or local zip.
    """
    version_label = "Uploaded ZIP app version matches release"
    gatekeeper_label = "Gatekeeper accepts uploaded zip"
    tag = f"v{version}"
    workdir = tempfile.mkdtemp(prefix="cb-gatekeeper-asset-")
    try:
        uploaded_zip, detail = _download_github_release_asset(tag, RELEASE_ZIP_ASSET, workdir)
        if not uploaded_zip:
            check(version_label, False, detail)
            check(gatekeeper_label, False, detail)
            return

        extract_dir = os.path.join(workdir, "extracted")
        os.makedirs(extract_dir, exist_ok=True)
        if not _extract_zip(uploaded_zip, extract_dir):
            detail = f"could not extract {RELEASE_ZIP_ASSET} from {tag}"
            check(version_label, False, detail)
            check(gatekeeper_label, False, detail)
            return

        app = os.path.join(extract_dir, f"{APP_NAME}.app")
        if not os.path.isdir(app):
            detail = f"{APP_NAME}.app not found inside zip"
            check(version_label, False, detail)
            check(gatekeeper_label, False, detail)
            return

        bundle_version, version_detail = _app_bundle_short_version(app)
        version_matches = bundle_version == version
        check(
            version_label,
            version_matches,
            bundle_version if version_matches else version_detail or f"{bundle_version or '(none)'} != {version}",
        )

        accepted, gatekeeper_detail = _gatekeeper_accepts_app(app)
        check(gatekeeper_label, accepted, gatekeeper_detail)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def check_dmg_contents(version):
    """Verify the uploaded GitHub release DMG contains the intended valid app."""
    contains_label = "Uploaded DMG mounts and contains app"
    version_label = "Uploaded DMG app version matches release"
    codesign_label = "Uploaded DMG app codesign valid"
    gatekeeper_label = "Uploaded DMG app Gatekeeper accepted"
    workdir = tempfile.mkdtemp(prefix="cb-dmg-asset-")
    mountpoint = tempfile.mkdtemp(prefix="cb-dmg-")
    attached = False
    try:
        tag = f"v{version}"
        uploaded_dmg, detail = _download_github_release_asset(tag, RELEASE_DMG_ASSET, workdir)
        if not uploaded_dmg:
            check(contains_label, False, detail)
            check(version_label, False, detail)
            check(codesign_label, False, detail)
            check(gatekeeper_label, False, detail)
            return

        if not _attach_dmg(uploaded_dmg, mountpoint):
            detail = f"could not attach {RELEASE_DMG_ASSET} from {tag}"
            check(contains_label, False, detail)
            check(version_label, False, detail)
            check(codesign_label, False, detail)
            check(gatekeeper_label, False, detail)
            return
        attached = True
        app = os.path.join(mountpoint, f"{APP_NAME}.app")
        present = os.path.isdir(app)
        missing_detail = f"{APP_NAME}.app missing in DMG"
        check(contains_label, present, f"{APP_NAME}.app" if present else missing_detail)
        if not present:
            check(version_label, False, missing_detail)
            check(codesign_label, False, missing_detail)
            check(gatekeeper_label, False, missing_detail)
            return

        bundle_version, version_detail = _app_bundle_short_version(app)
        version_matches = bundle_version == version
        check(
            version_label,
            version_matches,
            bundle_version if version_matches else version_detail or f"{bundle_version or '(none)'} != {version}",
        )

        codesign_ok, codesign_detail = _codesign_valid(app)
        check(codesign_label, codesign_ok, codesign_detail)

        gatekeeper_ok, gatekeeper_detail = _gatekeeper_accepts_app(app)
        check(gatekeeper_label, gatekeeper_ok, gatekeeper_detail)
    finally:
        if attached:
            _detach_dmg(mountpoint)
        shutil.rmtree(mountpoint, ignore_errors=True)
        shutil.rmtree(workdir, ignore_errors=True)


def check_cask_sha256(version):
    """Verify the published Homebrew cask sha256 matches the uploaded zip."""
    label = "Published Homebrew cask sha256 matches uploaded zip"
    content, detail = published_homebrew_cask()
    if not content:
        check(label, False, detail)
        return

    cask_sha = _active_cask_sha256(content)
    actual_sha, digest_detail = github_release_asset_sha256(version)
    if not actual_sha:
        check(label, False, digest_detail)
        return

    matches = cask_sha == actual_sha
    check(
        label,
        matches,
        "matches" if matches else f"cask {cask_sha or '(none)'} != uploaded zip {actual_sha}",
    )


def check_cask_arm64():
    """Verify the published cask enforces Apple Silicon via depends_on arch: :arm64."""
    label = "Published Homebrew cask enforces arm64"
    content, detail = published_homebrew_cask()
    if not content:
        check(label, False, detail)
        return

    found = _cask_has_active_arm64_dependency(content)
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
    """Verify the deployed appcast entry matches its enclosure archive."""
    url_label = "Appcast enclosure URL is canonical"
    sig_label = "Appcast edSignature verifies enclosure archive"
    len_label = "Appcast length matches enclosure archive size"

    sparkle_ns = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    root, detail = fetch_appcast_root()
    if root is None:
        check(url_label, False, detail)
        check(sig_label, False, detail)
        check(len_label, False, detail)
        return

    enclosure = _appcast_enclosure_for_version(root, version)
    if enclosure is None:
        check(url_label, False, f"no appcast item for v{version}")
        check(sig_label, False, f"no appcast item for v{version}")
        check(len_label, False, f"no appcast item for v{version}")
        return

    enclosure_url = enclosure.get("url", "")
    expected_url = expected_appcast_enclosure_url(version)
    url_matches = enclosure_url == expected_url
    check(url_label, url_matches, enclosure_url or "missing url")
    if not url_matches:
        check(sig_label, False, "enclosure URL mismatch")
        check(len_label, False, "enclosure URL mismatch")
        return

    workdir = tempfile.mkdtemp(prefix="cb-appcast-asset-")
    try:
        enclosure_zip, detail = _download_url_to_file(
            enclosure_url,
            os.path.join(workdir, RELEASE_ZIP_ASSET),
        )
        if not enclosure_zip:
            check(sig_label, False, detail)
            check(len_label, False, detail)
            return

        ed_signature = enclosure.get(f"{{{sparkle_ns}}}edSignature")
        if ed_signature:
            verified, verify_detail = verify_sparkle_update_signature(enclosure_zip, ed_signature)
            check(sig_label, verified, verify_detail)
        else:
            check(sig_label, False, "missing edSignature")

        zip_size = os.path.getsize(enclosure_zip)
        length_attr = enclosure.get("length")
        try:
            length_matches = length_attr is not None and int(length_attr) == zip_size
        except ValueError:
            length_matches = False
        length_detail = (
            f"{zip_size} bytes"
            if length_matches
            else f"appcast length {length_attr} != enclosure archive {zip_size}"
        )
        check(
            len_label,
            length_matches,
            length_detail,
        )
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


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
    check_gatekeeper_zip(version)
    check_dmg_contents(version)
    check_cask_sha256(version)
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
