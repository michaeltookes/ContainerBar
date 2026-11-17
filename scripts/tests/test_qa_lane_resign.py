#!/usr/bin/env python3
"""CB-124: resign.sh stages, signs by hash, verifies, then installs; provenance for branch candidates."""
from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from qa_lane_fakes import LANE_DIR

RESIGN = os.path.join(LANE_DIR, "resign.sh")


def make_cert(root: Path, name: str) -> tuple[Path, str]:
    key, pem, der = root / (name + ".key"), root / (name + ".pem"), root / (name + ".der")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", str(key), "-out", str(pem),
                    "-days", "2", "-subj", "/CN=" + name], check=True, capture_output=True)
    subprocess.run(["openssl", "x509", "-in", str(pem), "-outform", "der", "-out", str(der)], check=True)
    out = subprocess.run(["openssl", "x509", "-inform", "der", "-in", str(der), "-noout", "-fingerprint", "-sha1"],
                         check=True, capture_output=True, text=True).stdout
    return der, out.split("=")[1].strip().replace(":", "")


FAKE_CODESIGN = r"""#!/bin/bash
# Fake codesign: state lives in the bundle's .sig file (the leaf cert name) and the log.
echo "codesign $*" >> "$FAKE_LOG"
app="${@: -1}"
case "$*" in
  *--extract-certificates*) pre=$2; pre=${pre#--extract-certificates=}
    [ -f "$app/.sig" ] || exit 1; cp "$FAKE_DER_DIR/$(cat "$app/.sig").der" "${pre}0"; exit 0 ;;
  *"-d --entitlements"*) [ -f "$app/.ents" ] && echo "<plist/>"; exit 0 ;;
  *-dvv*) [ -f "$app/.sig" ] || exit 1
    if [ "$(cat "$app/.sig")" = release ]; then echo "Authority=Developer ID Application: x" >&2; else echo "Authority=Apple Development: x" >&2; fi
    echo "Identifier=${FAKE_IDENT:-com.tookes.ContainerBar}" >&2; exit 0 ;;
  *--verify*) [ "$FAKE_VERIFY_FAIL" = 1 ] && { echo "a sealed resource is missing" >&2; exit 1; }; [ -f "$app/.sig" ]; exit $? ;;
  *--sign*) [ "$FAKE_SIGN_FAIL" = 1 ] && { echo "errSecInternalComponent" >&2; exit 1; }
    id=${*#*--sign }; id=${id%% *}
    echo "$FAKE_SIGNER" > "$app/.sig"; exit 0 ;;
esac
"""


class ResignTests(unittest.TestCase):
    def setUp(self):
        if not os.path.exists("/usr/bin/plutil") or not shutil.which("openssl"):
            self.skipTest("needs macOS plutil and openssl")
        self.root = Path(tempfile.mkdtemp(prefix="cbqa-resign-"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        r = self.root
        self.ws, self.app = r / "ws", r / "Applications" / "ContainerBar.app"
        (self.ws / "qa" / "containerbar").mkdir(parents=True)
        (r / "bin").mkdir(); (r / "der").mkdir(); self.app.parent.mkdir()
        self.der_a, self.hash_a = make_cert(r / "der", "active")
        _, self.hash_b = make_cert(r / "der", "other")
        (r / "bin" / "codesign").write_text(FAKE_CODESIGN)
        (r / "bin" / "security").write_text(
            '#!/bin/bash\necho "  1) %s \\"Apple Development: x\\""\n' % self.hash_a)
        (r / "bin" / "xattr").write_text(
            '#!/bin/bash\napp="${@: -1}"\ncase "$1" in -dr) [ "$FAKE_XATTR_STUCK" = 1 ] || rm -f "$app/.quar" ;;\n'
            '-lr) [ -f "$app/.quar" ] && echo "$app: com.apple.quarantine: 0083" ;; esac\nexit 0\n')
        (r / "bin" / "pgrep").write_text('#!/bin/bash\n[ -f "$FAKE_RUNNING" ]\n')
        (r / "bin" / "osascript").write_text('#!/bin/bash\necho "osascript $*" >> "$FAKE_LOG"\n'
                                             '[ "$FAKE_QUIT_REFUSES" = 1 ] || rm -f "$FAKE_RUNNING"\n')
        for n in ("codesign", "security", "xattr", "pgrep", "osascript"):
            (r / "bin" / n).chmod(0o755)
        self.log = r / "calls.log"
        self.set_hash(self.hash_a)
        self.ent = self.ws / "qa" / "containerbar" / "ContainerBar.entitlements"
        self.ent.write_text("<plist/>")
        self.cand = r / "cand" / "ContainerBar.app"
        self.make_app(self.cand, "2.1.0", "9", ".ents")
        self.make_app(self.app, "2.0.4", "7")
        (self.app / ".sig").write_text("release")
        self.env = dict(os.environ, CBQA_WORKSPACE=str(self.ws), CBQA_APP_PATH=str(self.app), TMPDIR=str(r),
                        PATH=str(r / "bin") + ":" + os.environ["PATH"], FAKE_LOG=str(self.log),
                        FAKE_DER_DIR=str(r / "der"), FAKE_SIGNER="active", FAKE_SIGN_FAIL="0", FAKE_VERIFY_FAIL="0",
                        FAKE_RUNNING=str(r / "running"), CBQA_QUIT_POLL="0", FAKE_XATTR_STUCK="0",
                        FAKE_QUIT_REFUSES="0")

    def set_hash(self, value):
        (self.ws / "qa" / "containerbar" / "lane.env").write_text("CBQA_SIGNING_IDENTITY_HASH=%s\n" % value)

    def make_app(self, path, version, build, *flags, ident="com.tookes.ContainerBar"):
        (path / "Contents").mkdir(parents=True)
        with open(path / "Contents" / "Info.plist", "wb") as f:
            plistlib.dump({"CFBundleShortVersionString": version, "CFBundleVersion": build,
                           "CFBundleIdentifier": ident}, f)
        for flag in flags:
            (path / flag).write_text("")

    def run_resign(self, *args, **env):
        return subprocess.run(["/bin/bash", RESIGN, *args], env=dict(self.env, **env), capture_output=True, text=True)

    def installed_version(self):
        return plistlib.loads((self.app / "Contents" / "Info.plist").read_bytes())["CFBundleVersion"]

    def test_signs_staged_copy_then_replaces_and_records(self):
        done = self.run_resign(str(self.cand), "abc1234")
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertEqual(self.installed_version(), "9")
        self.assertEqual((self.app / ".sig").read_text().strip(), "active")
        record = (self.ws / "qa" / "containerbar" / "branch-candidate.env").read_text()
        self.assertIn("VERSION_BUILD=2.1.0-9", record)
        self.assertIn("SHA=abc1234", record)
        self.assertIn("IDENTITY_HASH=" + self.hash_a, record)
        calls = self.log.read_text()
        self.assertIn("--sign " + self.hash_a, calls)          # selected by hash, never by name
        self.assertNotIn("Apple Development", calls)
        self.assertIn("staged/ContainerBar.app", calls)
        self.assertNotIn("--sign %s %s" % (self.hash_a, self.app), calls)
        self.assertFalse((self.ws / "artifacts" / "containerbar-qa" / "staged").exists())

    def test_entitlements_only_when_the_build_has_them(self):
        self.run_resign(str(self.cand), "abc")
        self.assertIn("--entitlements " + str(self.ent), self.log.read_text())
        self.log.unlink()
        plain = self.root / "plain" / "ContainerBar.app"
        self.make_app(plain, "2.1.0", "10")
        self.assertEqual(self.run_resign(str(plain), "abc").returncode, 0)
        self.assertNotIn("--sign " + self.hash_a + " --entitlements", self.log.read_text())

    def test_entitled_build_without_workspace_copy_blocks(self):
        self.ent.unlink()
        done = self.run_resign(str(self.cand), "abc")
        self.assertEqual(done.returncode, 3)
        self.assertIn("BLOCKED qa-signing-failed", done.stdout)
        self.assertEqual(self.installed_version(), "7")

    def test_sign_or_verify_failure_installs_nothing(self):
        for knob in ("FAKE_SIGN_FAIL", "FAKE_VERIFY_FAIL"):
            done = self.run_resign(str(self.cand), "abc", **{knob: "1"})
            self.assertEqual(done.returncode, 3, knob)
            self.assertTrue(done.stdout.startswith("BLOCKED qa-signing-failed: "), done.stdout)
            self.assertEqual(self.installed_version(), "7", knob)
            self.assertEqual((self.app / ".sig").read_text().strip(), "release")
            self.assertFalse((self.ws / "qa" / "containerbar" / "branch-candidate.env").exists())
            self.assertFalse((self.ws / "artifacts" / "containerbar-qa" / "staged").exists())

    def test_wrong_signer_installs_nothing(self):
        done = self.run_resign(str(self.cand), "abc", FAKE_SIGNER="other")
        self.assertEqual(done.returncode, 3)
        self.assertEqual(self.installed_version(), "7")

    def test_identity_missing_or_not_listed_is_qa_identity_invalid(self):
        for value in ("", "not-a-hash", self.hash_b):
            self.set_hash(value)
            done = self.run_resign(str(self.cand), "abc")
            self.assertEqual((done.returncode, done.stdout.strip()), (4, "BLOCKED qa-identity-invalid"), value)
            self.assertEqual(self.installed_version(), "7")

    def test_provenance_is_release_without_a_record(self):
        done = self.run_resign("--provenance")
        self.assertEqual((done.returncode, done.stdout.strip()), (0, "mode=release"))

    def test_provenance_of_an_installed_branch_candidate(self):
        self.assertEqual(self.run_resign(str(self.cand), "abc1234").returncode, 0)
        done = self.run_resign("--provenance")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("mode=branch-candidate", done.stdout)
        self.assertIn("version-build=2.1.0-9", done.stdout)
        self.assertIn("branch-sha=abc1234", done.stdout)
        self.assertIn("identity=" + self.hash_a, done.stdout)
        self.assertTrue(done.stdout.strip().endswith("provenance=ok"))

    def test_provenance_fails_on_another_identity_or_a_changed_config(self):
        self.assertEqual(self.run_resign(str(self.cand), "abc").returncode, 0)
        (self.app / ".sig").write_text("other")
        done = self.run_resign("--provenance")
        self.assertEqual(done.returncode, 1)
        self.assertIn("provenance=FAIL signing identity differs", done.stdout)
        (self.app / ".sig").write_text("active")
        self.set_hash(self.hash_b)
        self.assertIn("provenance=FAIL configured identity invalid", self.run_resign("--provenance").stdout)

    def test_a_released_build_over_a_stale_record_is_judged_as_release(self):
        self.assertEqual(self.run_resign(str(self.cand), "abc").returncode, 0)
        shutil.rmtree(self.app); self.make_app(self.app, "2.0.5", "8")
        self.assertEqual(self.run_resign("--provenance").stdout.strip(), "mode=release")

    def test_developer_id_build_with_the_same_version_build_is_release(self):
        # Codex r2 P2: a leftover record must not make a Developer ID build a branch candidate.
        self.assertEqual(self.run_resign(str(self.cand), "abc").returncode, 0)
        (self.app / ".sig").write_text("release")
        self.assertEqual(self.run_resign("--provenance").stdout.strip(), "mode=release")

    def test_running_app_is_quit_gracefully_before_the_replace(self):
        Path(self.env["FAKE_RUNNING"]).write_text("")
        done = self.run_resign(str(self.cand), "abc")
        self.assertEqual(done.returncode, 0, done.stdout)
        self.assertIn("relaunch required", done.stdout)
        self.assertIn('tell application id "com.tookes.ContainerBar" to quit', self.log.read_text())
        self.assertEqual(self.installed_version(), "9")

    def test_app_that_will_not_quit_blocks_and_installs_nothing(self):
        Path(self.env["FAKE_RUNNING"]).write_text("")
        done = self.run_resign(str(self.cand), "abc", FAKE_QUIT_REFUSES="1")
        self.assertEqual(done.returncode, 5)
        self.assertIn("BLOCKED restore-failed", done.stdout)
        self.assertEqual(self.installed_version(), "7")
        self.assertFalse((self.ws / "qa" / "containerbar" / "branch-candidate.env").exists())

    def test_quarantine_is_stripped_from_the_staged_copy(self):
        (self.cand / ".quar").write_text("")
        self.assertEqual(self.run_resign(str(self.cand), "abc").returncode, 0)
        self.assertFalse((self.app / ".quar").exists())

    def test_quarantine_that_cannot_be_removed_blocks(self):
        (self.cand / ".quar").write_text("")
        done = self.run_resign(str(self.cand), "abc", FAKE_XATTR_STUCK="1")
        self.assertEqual(done.returncode, 3)
        self.assertIn("quarantine", done.stdout)
        self.assertEqual(self.installed_version(), "7")

    def test_hunt_build_is_never_resigned(self):
        hunt = self.root / "hunt" / "ContainerBar.app"
        self.make_app(hunt, "2.1.0", "9", ident="com.tookes.ContainerBar.hunt")
        done = self.run_resign(str(hunt), "abc")
        self.assertEqual(done.returncode, 3)
        self.assertIn("com.tookes.ContainerBar.hunt", done.stdout)
        self.assertNotIn("--sign", self.log.read_text() if self.log.exists() else "")
        self.assertEqual(self.installed_version(), "7")

    def test_signed_identifier_must_still_match(self):
        done = self.run_resign(str(self.cand), "abc", FAKE_IDENT="com.other.app")
        self.assertEqual(done.returncode, 3)
        self.assertIn("com.other.app", done.stdout)
        self.assertEqual(self.installed_version(), "7")

    def test_provenance_marker_for_unused_check(self):
        self.assertEqual(self.run_resign("--provenance").stdout.strip(), "mode=release")


if __name__ == "__main__":
    unittest.main()
