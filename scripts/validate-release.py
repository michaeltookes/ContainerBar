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
import stat
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
SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
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
REQUIRED_EXECUTABLE_ARCH = "arm64"
REQUIRED_APPCAST_HARDWARE_REQUIREMENT = "arm64"
PRODUCTION_TEAM_ID = "6739LM5834"
PRODUCTION_SIGNING_AUTHORITY = "Developer ID Application: MICHAEL ARRINGTON TOOKES (6739LM5834)"
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


def _active_cask_version(content):
    """Return the active cask version, ignoring commented-out lines."""
    match = re.search(r'(?m)^\s*version\s+"([^"]+)"', content)
    return match.group(1) if match else ""


def _active_cask_url(content):
    """Return the active cask URL, ignoring commented-out lines."""
    match = re.search(r'(?m)^\s*url\s+"([^"]+)"', content)
    return match.group(1) if match else ""


def expected_homebrew_cask_url(version):
    """Return the canonical Homebrew cask URL for the release zip."""
    return f"https://github.com/{GITHUB_REPO}/releases/download/v{version}/{RELEASE_ZIP_ASSET}"


def _resolved_cask_url(url, cask_version, requested_version):
    """Resolve the simple Homebrew #{version} interpolation used by the cask."""
    version = cask_version or requested_version
    return url.replace("#{version}", version)


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
    return expected_homebrew_cask_url(version)


def _plist_string(plist, key):
    """Return a plist value as a stripped string."""
    value = plist.get(key, "")
    return str(value).strip() if value is not None else ""


def _read_bundle_version_fields(plist_path):
    """Return bundle short version, build number, and per-field detail strings."""
    try:
        with open(plist_path, "rb") as handle:
            plist = plistlib.load(handle)
    except Exception as exc:
        detail = f"could not read {plist_path}: {exc}"
        return "", "", detail, detail

    short_version = _plist_string(plist, "CFBundleShortVersionString")
    build_number = _plist_string(plist, "CFBundleVersion")
    version_detail = "" if short_version else "CFBundleShortVersionString missing"
    build_detail = "" if build_number else "CFBundleVersion missing"
    return short_version, build_number, version_detail, build_detail


def _read_bundle_identifier(plist_path):
    """Return CFBundleIdentifier and detail from a bundle Info.plist."""
    try:
        with open(plist_path, "rb") as handle:
            plist = plistlib.load(handle)
    except Exception as exc:
        detail = f"could not read {plist_path}: {exc}"
        return "", detail

    bundle_id = _plist_string(plist, "CFBundleIdentifier")
    return bundle_id, "" if bundle_id else "CFBundleIdentifier missing"


def _info_plist_versions():
    """Return expected version fields from the distribution Info.plist."""
    return _read_bundle_version_fields(INFO_PLIST)


def expected_info_plist_build_number():
    """Return the expected CFBundleVersion from Distribution/Info.plist."""
    _, build_number, _, build_detail = _info_plist_versions()
    return build_number, build_detail


def expected_bundle_identifier():
    """Return the expected CFBundleIdentifier from Distribution/Info.plist."""
    return _read_bundle_identifier(INFO_PLIST)


def _app_bundle_versions(app_path):
    """Return CFBundleShortVersionString and CFBundleVersion from an app bundle."""
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    return _read_bundle_version_fields(plist_path)


def _app_bundle_identifier(app_path):
    """Return CFBundleIdentifier from an app bundle."""
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    return _read_bundle_identifier(plist_path)


def _app_bundle_sparkle_feed_url(app_path):
    """Return SUFeedURL from an app bundle."""
    plist_path = os.path.join(app_path, "Contents", "Info.plist")
    try:
        with open(plist_path, "rb") as handle:
            plist = plistlib.load(handle)
    except Exception as exc:
        detail = f"could not read {plist_path}: {exc}"
        return "", detail

    feed_url = _plist_string(plist, "SUFeedURL")
    return feed_url, "" if feed_url else "SUFeedURL missing"


def _app_bundle_short_version(app_path):
    """Return CFBundleShortVersionString from an app bundle."""
    version, _, version_detail, _ = _app_bundle_versions(app_path)
    return version, version_detail


def _check_app_bundle_version_and_build(app_path, release_version, version_label, build_label):
    """Validate an app bundle's marketing version and build number."""
    bundle_version, bundle_build, version_detail, build_detail = _app_bundle_versions(app_path)
    version_matches = bundle_version == release_version
    check(
        version_label,
        version_matches,
        bundle_version if version_matches else version_detail or f"{bundle_version or '(none)'} != {release_version}",
    )

    expected_build, expected_detail = expected_info_plist_build_number()
    build_matches = bool(expected_build) and bundle_build == expected_build
    if build_matches:
        detail = bundle_build
    elif expected_detail:
        detail = expected_detail
    elif build_detail:
        detail = build_detail
    else:
        detail = f"{bundle_build or '(none)'} != {expected_build}"
    check(build_label, build_matches, detail)


def _check_app_bundle_sparkle_feed_url(app_path, label):
    """Validate an app bundle points Sparkle at the canonical deployed appcast."""
    feed_url, detail = _app_bundle_sparkle_feed_url(app_path)
    feed_matches = feed_url == APPCAST_URL
    check(
        label,
        feed_matches,
        feed_url if feed_matches else detail or f"SUFeedURL {feed_url or '(none)'} != {APPCAST_URL}",
    )


def _codesign_verify(path, extra_options=()):
    """Return whether a path passes codesign verification with extra options."""
    codesign_bin = shutil.which("codesign")
    if not codesign_bin:
        return False, "codesign not found"

    try:
        result = subprocess.run(
            [codesign_bin, "--verify", *extra_options, "--verbose=2", path],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        return False, f"codesign execution failed: {exc}"

    combined = (result.stdout + result.stderr).strip()
    return result.returncode == 0, combined if combined else "verified"


def _codesign_valid(app_path):
    """Return whether an app bundle passes strict codesign verification."""
    return _codesign_verify(app_path, ("--deep", "--strict"))


def _codesign_valid_container(path):
    """Return whether a signed release container passes codesign verification."""
    return _codesign_verify(path)


def _codesign_metadata(path):
    """Return codesign display metadata for a signed artifact."""
    codesign_bin = shutil.which("codesign")
    if not codesign_bin:
        return None, "codesign not found"

    try:
        result = subprocess.run(
            [codesign_bin, "-dv", "--verbose=4", path],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        return None, f"codesign execution failed: {exc}"

    combined = (result.stdout + result.stderr).strip()
    if result.returncode != 0:
        return None, combined if combined else "codesign display failed"

    metadata = {}
    authorities = []
    for raw_line in combined.splitlines():
        line = raw_line.strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key == "Authority":
            authorities.append(value)
        else:
            metadata[key] = value
    metadata["Authority"] = authorities
    return metadata, combined


def _codesign_designated_requirement(path):
    """Return the app's designated code signing requirement text."""
    codesign_bin = shutil.which("codesign")
    if not codesign_bin:
        return "", "codesign not found"

    try:
        result = subprocess.run(
            [codesign_bin, "-d", "-r-", path],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        return "", f"codesign execution failed: {exc}"

    combined = (result.stdout + result.stderr).strip()
    if result.returncode != 0:
        return "", combined if combined else "codesign requirement display failed"

    return combined, combined


def _production_signing_identity_valid(app_path):
    """Return whether an app is signed as the production app bundle."""
    expected_id, expected_detail = expected_bundle_identifier()
    if not expected_id:
        return False, expected_detail

    bundle_id, bundle_detail = _app_bundle_identifier(app_path)
    if bundle_id != expected_id:
        return False, bundle_detail or f"CFBundleIdentifier {bundle_id or '(none)'} != {expected_id}"

    metadata, detail = _codesign_metadata(app_path)
    if metadata is None:
        return False, detail

    team_id = metadata.get("TeamIdentifier", "")
    if team_id != PRODUCTION_TEAM_ID:
        return False, f"TeamIdentifier {team_id or '(none)'} != {PRODUCTION_TEAM_ID}"

    authorities = metadata.get("Authority", [])
    if PRODUCTION_SIGNING_AUTHORITY not in authorities:
        authority_detail = ", ".join(authorities) if authorities else "(none)"
        return False, f"Authority {authority_detail} missing {PRODUCTION_SIGNING_AUTHORITY}"

    requirement, requirement_detail = _codesign_designated_requirement(app_path)
    expected_identifier_requirement = f'identifier "{expected_id}"'
    if expected_identifier_requirement not in requirement:
        return False, f"designated requirement missing {expected_identifier_requirement}: {requirement_detail}"

    return True, f"{PRODUCTION_SIGNING_AUTHORITY}; TeamIdentifier={team_id}; {expected_identifier_requirement}"


def _stapler_valid(path):
    """Return whether a release artifact has a valid stapled notarization ticket."""
    xcrun_bin = shutil.which("xcrun")
    if not xcrun_bin:
        return False, "xcrun not found"
    try:
        result = subprocess.run(
            [xcrun_bin, "stapler", "validate", path],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        return False, f"stapler execution failed: {exc}"

    combined = (result.stdout + result.stderr).strip()
    return result.returncode == 0, combined if combined else "valid"


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
    plist_version, build_number, version_detail, build_detail = _info_plist_versions()
    check(
        "Info.plist version",
        plist_version == version,
        plist_version if plist_version == version else version_detail or plist_version,
    )
    check("Info.plist build", build_number != "", build_number or build_detail)


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
    """Verify the published Homebrew cask has the correct version and URL."""
    version_label = "Published Homebrew cask version"
    url_label = "Published Homebrew cask URL is canonical"
    content, detail = published_homebrew_cask()
    if not content:
        check(version_label, False, detail)
        check(url_label, False, detail)
        return

    cask_version = _active_cask_version(content)
    check(version_label, cask_version == version, cask_version)

    cask_url = _active_cask_url(content)
    resolved_url = _resolved_cask_url(cask_url, cask_version, version)
    expected_url = expected_homebrew_cask_url(version)
    url_matches = resolved_url == expected_url
    check(url_label, url_matches, resolved_url or "missing url")


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

    found = False
    # Check both child elements and enclosure attributes
    for item in root.findall(".//item"):
        svs_elem = item.find(f"{{{SPARKLE_NS}}}shortVersionString")
        if svs_elem is not None and svs_elem.text == version:
            found = True
            break
        for enclosure in item.findall("enclosure"):
            if enclosure.get(f"{{{SPARKLE_NS}}}shortVersionString") == version:
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
    """Verify the local app binary can resolve embedded frameworks."""
    _check_framework_rpath(APP_BUNDLE, "App framework rpath valid")


def _check_framework_rpath(app_path, label):
    """Verify an app binary can resolve embedded frameworks from Contents/Frameworks."""
    binary = app_executable_path(app_path)
    sparkle_framework = os.path.join(app_path, "Contents", "Frameworks", "Sparkle.framework")

    if not os.path.isfile(binary):
        check(label, False, f"binary not found: {binary}")
        return

    if not os.path.isdir(sparkle_framework):
        check(label, False, f"framework not found: {sparkle_framework}")
        return

    otool_bin = shutil.which("otool")
    if not otool_bin:
        check(label, False, "otool not found")
        return

    try:
        result = subprocess.run(
            [otool_bin, "-l", binary],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        check(label, False, f"otool execution failed: {exc}")
        return

    if result.returncode != 0:
        combined = (result.stdout + result.stderr).strip()
        check(label, False, combined if combined else "otool failed")
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
        label,
        "@executable_path/../Frameworks" in rpaths,
        ", ".join(rpaths) if rpaths else "no LC_RPATH entries found",
    )


def app_executable_path(app_path=None):
    """Return the packaged app executable path."""
    bundle = app_path or APP_BUNDLE
    return os.path.join(bundle, "Contents", "MacOS", APP_NAME)


def check_no_swiftpm_release_resource_path():
    """Verify the local binary does not embed SwiftPM release resource paths."""
    _check_no_swiftpm_release_resource_path(
        APP_BUNDLE,
        "No SwiftPM release resource path embedded",
    )


def _check_no_swiftpm_release_resource_path(app_path, label):
    """Verify a binary does not embed SwiftPM release resource fallback paths."""
    binary = app_executable_path(app_path)
    if not os.path.isfile(binary):
        check(label, False, f"binary not found: {binary}")
        return
    with open(binary, "rb") as f:
        binary_contents = f.read()
    embedded_path = next(
        (path for path in BROKEN_SWIFTPM_RELEASE_PATHS if path in binary_contents),
        None,
    )
    check(
        label,
        embedded_path is None,
        (
            f"binary references {embedded_path.decode()}; SwiftPM resource accessor would crash on other Macs"
            if embedded_path
            else ""
        ),
    )


def check_required_resource_bundles():
    """Verify release-critical resource bundles are packaged inside the app."""
    _check_required_resource_bundles(APP_BUNDLE, "Required resource bundles packaged")


def _check_required_resource_bundles(app_path, label):
    """Verify release-critical resource bundles are packaged inside an app."""
    resources_dir = os.path.join(app_path, "Contents", "Resources")
    missing = [
        name
        for name in REQUIRED_RESOURCE_BUNDLES
        if not os.path.isdir(os.path.join(resources_dir, name))
    ]
    check(
        label,
        not missing,
        ", ".join(missing) if missing else ", ".join(REQUIRED_RESOURCE_BUNDLES),
    )


def _check_executable_architecture(app_path, label):
    """Verify an app executable is exactly the required release architecture."""
    binary = app_executable_path(app_path)
    if not os.path.isfile(binary):
        check(label, False, f"binary not found: {binary}")
        return

    lipo_bin = shutil.which("lipo")
    if not lipo_bin:
        check(label, False, "lipo not found")
        return

    try:
        result = subprocess.run(
            [lipo_bin, "-archs", binary],
            capture_output=True,
            text=True,
            check=False,
        )
    except (FileNotFoundError, OSError) as exc:
        check(label, False, f"lipo execution failed: {exc}")
        return

    if result.returncode != 0:
        combined = (result.stdout + result.stderr).strip()
        check(label, False, combined if combined else "lipo failed")
        return

    archs = result.stdout.split()
    check(
        label,
        archs == [REQUIRED_EXECUTABLE_ARCH],
        " ".join(archs) if archs else "no architectures reported",
    )


def _app_bundle_content_hash(app_path):
    """Return a deterministic hash of app bundle file and symlink contents."""
    if not os.path.isdir(app_path):
        return "", f"app not found: {app_path}"

    digest = hashlib.sha256()
    try:
        for root, dirnames, filenames in os.walk(app_path, topdown=True, followlinks=False):
            dirnames.sort()
            filenames.sort()
            for name in sorted([*dirnames, *filenames]):
                path = os.path.join(root, name)
                rel_path = os.path.relpath(path, app_path).replace(os.sep, "/")
                info = os.lstat(path)
                mode = stat.S_IMODE(info.st_mode)
                digest.update(rel_path.encode("utf-8"))
                digest.update(b"\0")

                if stat.S_ISLNK(info.st_mode):
                    digest.update(b"L")
                    digest.update(os.readlink(path).encode("utf-8"))
                elif stat.S_ISDIR(info.st_mode):
                    digest.update(b"D")
                    digest.update(str(mode).encode("ascii"))
                elif stat.S_ISREG(info.st_mode):
                    digest.update(b"F")
                    digest.update(str(mode).encode("ascii"))
                    with open(path, "rb") as handle:
                        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                            digest.update(chunk)
                else:
                    digest.update(b"O")
                    digest.update(str(info.st_mode).encode("ascii"))
                digest.update(b"\0")
    except OSError as exc:
        return "", f"could not hash {app_path}: {exc}"

    return digest.hexdigest(), ""


def _check_app_bundle_content_match(zip_app, dmg_app, label):
    """Verify two app bundle trees have identical on-disk contents."""
    zip_hash, zip_detail = _app_bundle_content_hash(zip_app)
    if not zip_hash:
        check(label, False, zip_detail)
        return

    dmg_hash, dmg_detail = _app_bundle_content_hash(dmg_app)
    if not dmg_hash:
        check(label, False, dmg_detail)
        return

    matches = zip_hash == dmg_hash
    check(
        label,
        matches,
        (
            f"bundle hash {zip_hash[:12]}"
            if matches
            else f"zip bundle hash {zip_hash[:12]} != dmg bundle hash {dmg_hash[:12]}"
        ),
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
    target and validate its packaged contents rather than trusting the loose
    dist/ bundle or local zip.
    """
    version_label = "Uploaded ZIP app version matches release"
    build_label = "Uploaded ZIP app build matches Info.plist"
    feed_label = "Uploaded ZIP app Sparkle feed URL is canonical"
    gatekeeper_label = "Gatekeeper accepts uploaded zip"
    staple_label = "Uploaded ZIP app stapled ticket valid"
    signing_label = "Uploaded ZIP app production signing identity"
    rpath_label = "Uploaded ZIP app framework rpath valid"
    resources_label = "Uploaded ZIP required resource bundles packaged"
    swiftpm_path_label = "Uploaded ZIP has no SwiftPM release resource path embedded"
    arch_label = f"Uploaded ZIP executable is {REQUIRED_EXECUTABLE_ARCH}-only"
    bundle_labels = (version_label, build_label, feed_label)
    notarization_labels = (gatekeeper_label, staple_label)
    signing_labels = (signing_label,)
    packaging_labels = (rpath_label, resources_label, swiftpm_path_label, arch_label)
    tag = f"v{version}"
    workdir = tempfile.mkdtemp(prefix="cb-gatekeeper-asset-")
    try:
        uploaded_zip, detail = _download_github_release_asset(tag, RELEASE_ZIP_ASSET, workdir)
        if not uploaded_zip:
            for label in bundle_labels:
                check(label, False, detail)
            for label in notarization_labels:
                check(label, False, detail)
            for label in signing_labels:
                check(label, False, detail)
            for label in packaging_labels:
                check(label, False, detail)
            return

        extract_dir = os.path.join(workdir, "extracted")
        os.makedirs(extract_dir, exist_ok=True)
        if not _extract_zip(uploaded_zip, extract_dir):
            detail = f"could not extract {RELEASE_ZIP_ASSET} from {tag}"
            for label in bundle_labels:
                check(label, False, detail)
            for label in notarization_labels:
                check(label, False, detail)
            for label in signing_labels:
                check(label, False, detail)
            for label in packaging_labels:
                check(label, False, detail)
            return

        app = os.path.join(extract_dir, f"{APP_NAME}.app")
        if not os.path.isdir(app):
            detail = f"{APP_NAME}.app not found inside zip"
            for label in bundle_labels:
                check(label, False, detail)
            for label in notarization_labels:
                check(label, False, detail)
            for label in signing_labels:
                check(label, False, detail)
            for label in packaging_labels:
                check(label, False, detail)
            return

        _check_app_bundle_version_and_build(app, version, version_label, build_label)
        _check_app_bundle_sparkle_feed_url(app, feed_label)

        accepted, gatekeeper_detail = _gatekeeper_accepts_app(app)
        check(gatekeeper_label, accepted, gatekeeper_detail)

        staple_ok, staple_detail = _stapler_valid(app)
        check(staple_label, staple_ok, staple_detail)

        signing_ok, signing_detail = _production_signing_identity_valid(app)
        check(signing_label, signing_ok, signing_detail)

        _check_framework_rpath(app, rpath_label)
        _check_required_resource_bundles(app, resources_label)
        _check_no_swiftpm_release_resource_path(app, swiftpm_path_label)
        _check_executable_architecture(app, arch_label)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def check_dmg_contents(version):
    """Verify the uploaded GitHub release DMG contains the intended valid app."""
    contains_label = "Uploaded DMG mounts and contains app"
    version_label = "Uploaded DMG app version matches release"
    build_label = "Uploaded DMG app build matches Info.plist"
    feed_label = "Uploaded DMG app Sparkle feed URL is canonical"
    codesign_label = "Uploaded DMG app codesign valid"
    signing_label = "Uploaded DMG app production signing identity"
    gatekeeper_label = "Uploaded DMG app Gatekeeper accepted"
    rpath_label = "Uploaded DMG app framework rpath valid"
    resources_label = "Uploaded DMG required resource bundles packaged"
    swiftpm_path_label = "Uploaded DMG has no SwiftPM release resource path embedded"
    arch_label = f"Uploaded DMG executable is {REQUIRED_EXECUTABLE_ARCH}-only"
    dmg_codesign_label = "Uploaded DMG container codesign valid"
    dmg_staple_label = "Uploaded DMG container stapled ticket valid"
    app_labels = (
        contains_label,
        version_label,
        build_label,
        feed_label,
        codesign_label,
        signing_label,
        gatekeeper_label,
    )
    packaging_labels = (rpath_label, resources_label, swiftpm_path_label, arch_label)
    container_labels = (dmg_codesign_label, dmg_staple_label)
    workdir = tempfile.mkdtemp(prefix="cb-dmg-asset-")
    mountpoint = tempfile.mkdtemp(prefix="cb-dmg-")
    attached = False
    try:
        tag = f"v{version}"
        uploaded_dmg, detail = _download_github_release_asset(tag, RELEASE_DMG_ASSET, workdir)
        if not uploaded_dmg:
            for label in app_labels + packaging_labels + container_labels:
                check(label, False, detail)
            return

        dmg_codesign_ok, dmg_codesign_detail = _codesign_valid_container(uploaded_dmg)
        check(dmg_codesign_label, dmg_codesign_ok, dmg_codesign_detail)

        dmg_staple_ok, dmg_staple_detail = _stapler_valid(uploaded_dmg)
        check(dmg_staple_label, dmg_staple_ok, dmg_staple_detail)

        if not _attach_dmg(uploaded_dmg, mountpoint):
            detail = f"could not attach {RELEASE_DMG_ASSET} from {tag}"
            for label in app_labels + packaging_labels:
                check(label, False, detail)
            return
        attached = True
        app = os.path.join(mountpoint, f"{APP_NAME}.app")
        present = os.path.isdir(app)
        missing_detail = f"{APP_NAME}.app missing in DMG"
        check(contains_label, present, f"{APP_NAME}.app" if present else missing_detail)
        if not present:
            for label in (
                version_label,
                build_label,
                feed_label,
                codesign_label,
                signing_label,
                gatekeeper_label,
                *packaging_labels,
            ):
                check(label, False, missing_detail)
            return

        _check_app_bundle_version_and_build(app, version, version_label, build_label)
        _check_app_bundle_sparkle_feed_url(app, feed_label)

        codesign_ok, codesign_detail = _codesign_valid(app)
        check(codesign_label, codesign_ok, codesign_detail)

        signing_ok, signing_detail = _production_signing_identity_valid(app)
        check(signing_label, signing_ok, signing_detail)

        gatekeeper_ok, gatekeeper_detail = _gatekeeper_accepts_app(app)
        check(gatekeeper_label, gatekeeper_ok, gatekeeper_detail)

        _check_framework_rpath(app, rpath_label)
        _check_required_resource_bundles(app, resources_label)
        _check_no_swiftpm_release_resource_path(app, swiftpm_path_label)
        _check_executable_architecture(app, arch_label)
    finally:
        if attached:
            _detach_dmg(mountpoint)
        shutil.rmtree(mountpoint, ignore_errors=True)
        shutil.rmtree(workdir, ignore_errors=True)


def check_uploaded_artifact_consistency(version):
    """Verify uploaded ZIP and DMG artifacts contain the same app bundle."""
    label = "Uploaded ZIP and DMG contain the same app"
    tag = f"v{version}"
    workdir = tempfile.mkdtemp(prefix="cb-artifact-consistency-")
    mountpoint = tempfile.mkdtemp(prefix="cb-artifact-consistency-dmg-")
    attached = False
    try:
        uploaded_zip, detail = _download_github_release_asset(tag, RELEASE_ZIP_ASSET, workdir)
        if not uploaded_zip:
            check(label, False, detail)
            return

        extract_dir = os.path.join(workdir, "zip")
        os.makedirs(extract_dir, exist_ok=True)
        if not _extract_zip(uploaded_zip, extract_dir):
            check(label, False, f"could not extract {RELEASE_ZIP_ASSET} from {tag}")
            return

        zip_app = os.path.join(extract_dir, f"{APP_NAME}.app")
        if not os.path.isdir(zip_app):
            check(label, False, f"{APP_NAME}.app not found inside zip")
            return

        uploaded_dmg, detail = _download_github_release_asset(tag, RELEASE_DMG_ASSET, workdir)
        if not uploaded_dmg:
            check(label, False, detail)
            return

        if not _attach_dmg(uploaded_dmg, mountpoint):
            check(label, False, f"could not attach {RELEASE_DMG_ASSET} from {tag}")
            return
        attached = True

        dmg_app = os.path.join(mountpoint, f"{APP_NAME}.app")
        if not os.path.isdir(dmg_app):
            check(label, False, f"{APP_NAME}.app missing in DMG")
            return

        _check_app_bundle_content_match(zip_app, dmg_app, label)
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


def _appcast_item_and_enclosure_for_version(root, version):
    """Return the appcast item and enclosure for version, or (None, None)."""
    for item in root.findall(".//item"):
        svs_elem = item.find(f"{{{SPARKLE_NS}}}shortVersionString")
        item_matches = svs_elem is not None and svs_elem.text == version
        for enclosure in item.findall("enclosure"):
            if item_matches or enclosure.get(f"{{{SPARKLE_NS}}}shortVersionString") == version:
                return item, enclosure
    return None, None


def _appcast_enclosure_for_version(root, version):
    """Return the <enclosure> element whose item matches version, or None."""
    _, enclosure = _appcast_item_and_enclosure_for_version(root, version)
    return enclosure


def _appcast_sparkle_version(item, enclosure):
    """Return sparkle:version from an enclosure attribute or item child."""
    attr_value = enclosure.get(f"{{{SPARKLE_NS}}}version") if enclosure is not None else ""
    if attr_value:
        return attr_value.strip()

    version_elem = item.find(f"{{{SPARKLE_NS}}}version") if item is not None else None
    return version_elem.text.strip() if version_elem is not None and version_elem.text else ""


def _appcast_hardware_requirements(item):
    """Return the comma-delimited Sparkle hardware requirements for an item."""
    requirements_elem = item.find(f"{{{SPARKLE_NS}}}hardwareRequirements") if item is not None else None
    if requirements_elem is None or not requirements_elem.text:
        return []

    return [
        requirement.strip()
        for requirement in requirements_elem.text.split(",")
        if requirement.strip()
    ]


def check_appcast_signature(version):
    """Verify the deployed appcast entry matches its enclosure archive."""
    url_label = "Appcast enclosure URL is canonical"
    build_label = "Appcast sparkle:version matches Info.plist build"
    hardware_label = "Appcast requires arm64 hardware"
    sig_label = "Appcast edSignature verifies enclosure archive"
    len_label = "Appcast length matches enclosure archive size"
    appcast_labels = (url_label, build_label, hardware_label, sig_label, len_label)

    root, detail = fetch_appcast_root()
    if root is None:
        for label in appcast_labels:
            check(label, False, detail)
        return

    item, enclosure = _appcast_item_and_enclosure_for_version(root, version)
    if enclosure is None:
        detail = f"no appcast item for v{version}"
        for label in appcast_labels:
            check(label, False, detail)
        return

    expected_build, expected_detail = expected_info_plist_build_number()
    appcast_build = _appcast_sparkle_version(item, enclosure)
    build_matches = bool(expected_build) and appcast_build == expected_build
    check(
        build_label,
        build_matches,
        appcast_build if build_matches else expected_detail or f"appcast {appcast_build or '(none)'} != Info.plist {expected_build}",
    )

    hardware_requirements = _appcast_hardware_requirements(item)
    expected_hardware_requirements = [REQUIRED_APPCAST_HARDWARE_REQUIREMENT]
    hardware_matches = hardware_requirements == expected_hardware_requirements
    check(
        hardware_label,
        hardware_matches,
        REQUIRED_APPCAST_HARDWARE_REQUIREMENT
        if hardware_matches
        else f"sparkle:hardwareRequirements {', '.join(hardware_requirements) or '(none)'} != {REQUIRED_APPCAST_HARDWARE_REQUIREMENT}",
    )

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

        ed_signature = enclosure.get(f"{{{SPARKLE_NS}}}edSignature")
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
    check_uploaded_artifact_consistency(version)
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
