"""Real-Git regressions for #115's source artifact scan, not release inspection.

Each scan runs a disposable script copy in a temporary repository with no
commits. Credential-shaped strings and private-state markers are synthetic and
assembled at runtime. Assertions never include captured output or fixture data.
Git is stubbed only to inject enumeration/search failures; other commands use
the real executable. This does not replace detect-secrets or inspect APK/IPA.
"""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tool/scan_artifacts.sh"
PASS = b"Security artifact scan: PASS"
CANARY = "synthetic" + "-artifact-scan-" + "not-for-output"


def credential_fixtures():
    """Cover the existing regex alternatives without literal usable secrets."""
    fixtures = {}
    for kind in ("", "RSA", "EC", "OPENSSH"):
        words = ["-----BEGIN", *([kind] if kind else []), "PRIVATE", "KEY-----"]
        fixtures["key-" + (kind or "generic")] = " ".join(words)
    fixtures["google-api"] = "AI" + "za" + "a" * 35
    fixtures["oauth"] = "ya" + "29." + "synthetic-token"
    for kind in "pousr":
        fixtures["github-" + kind] = "gh" + kind + "_" + "a" * 20
    for kind in "baprs":
        fixtures["slack-" + kind] = "xo" + "x" + kind + "-" + "a" * 10
    fixtures["private-key-field"] = json.dumps({"private" + "_key": "synthetic"})
    return fixtures


def marked(value):
    return (value + " " + CANARY + "\n").encode("utf-8")


class ArtifactScanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.git = shutil.which("git")
        if cls.git is None:
            raise RuntimeError("Real Git is required for artifact scan regressions")
        cls.git = str(Path(cls.git).resolve())

    def run_scan(self, files=None, *, untracked=None, replacements=None,
                 initialize=True, fault=None, unreadable=()):
        """Return captured bytes only; never place them in assertion messages."""
        original_script = SCRIPT.read_bytes()
        with tempfile.TemporaryDirectory(prefix="artifact scan fixture ") as folder:
            container = Path(folder)
            root = container / "repository"
            (root / "tool").mkdir(parents=True)
            script = root / "tool/scan_artifacts.sh"
            script.write_bytes(original_script)
            environment = {key: value for key, value in os.environ.items()
                           if not key.startswith("GIT_")}
            environment.update({
                "GIT_CONFIG_NOSYSTEM": "1",
                "GIT_CONFIG_GLOBAL": os.devnull,
                "GIT_TERMINAL_PROMPT": "0",
                "GIT_OPTIONAL_LOCKS": "0",
                "LC_ALL": "C",
            })
            if initialize:
                initialized = subprocess.run(
                    [self.git, "init", "--quiet"], cwd=root, env=environment,
                    capture_output=True, timeout=10,
                )
                self.assertTrue(initialized.returncode == 0, "Fixture Git init failed")
            tracked = {"apps/mobile/lib/benign.dart": b"final visible = true;\n",
                       **(files or {})}
            for relative, content in tracked.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
            if initialize:
                staged = subprocess.run(
                    [self.git, "add", "--", "tool/scan_artifacts.sh", *tracked],
                    cwd=root, env=environment, capture_output=True, timeout=10,
                )
                self.assertTrue(staged.returncode == 0, "Fixture Git staging failed")
            for relative, content in {**(untracked or {}), **(replacements or {})}.items():
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)

            probe = container / "fault-observed.json"
            if fault is not None:
                stub_directory = container / "stub-bin"
                stub_directory.mkdir()
                stub = stub_directory / "git"
                stub.write_text(self.git_stub(probe, fault), encoding="utf-8")
                stub.chmod(0o755)
                environment["PATH"] = str(stub_directory) + os.pathsep + environment["PATH"]

            before = self.input_fingerprints(root)
            original_modes = {}
            try:
                for relative in unreadable:
                    path = root / relative
                    original_modes[path] = path.stat().st_mode & 0o777
                    path.chmod(0)
                    self.assertFalse(os.access(path, os.R_OK),
                                     "Unreadable fixture requires a non-root test user")
                    probe_result = subprocess.run(
                        [self.git, "grep", "-EI", "-e", "synthetic-no-match", "--", relative],
                        cwd=root, env=environment, capture_output=True, timeout=10,
                    )
                    self.assertTrue(probe_result.returncode != 0 and bool(probe_result.stderr),
                                    "Real Git did not exercise the unreadable-file diagnostic")
                result = subprocess.run(
                    ["bash", "tool/scan_artifacts.sh"], cwd=root, env=environment,
                    capture_output=True, timeout=10,
                )
            finally:
                for path, mode in original_modes.items():
                    path.chmod(mode)
            self.assertTrue(before == self.input_fingerprints(root),
                            "The scanner changed its source files or Git index")
            self.assertTrue(SCRIPT.read_bytes() == original_script,
                            "The repository scanner was changed by the regression")
            if fault is not None:
                self.assertTrue(probe.exists(), "Requested Git failure was not exercised")
                observed = json.loads(probe.read_text(encoding="utf-8"))
                self.assertFalse(observed["quiet"],
                                 "Git grep must not use quiet mode to hide partial errors")
            return result

    @staticmethod
    def input_fingerprints(root):
        paths = [path for path in root.rglob("*")
                 if path.is_file() and ".git" not in path.relative_to(root).parts]
        index = root / ".git/index"
        if index.exists():
            paths.append(index)
        return {str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).digest()
                for path in paths}

    def git_stub(self, probe, fault):
        phase, code, partial = fault
        # The stub lives outside the temporary repository. It cannot influence
        # normal init/add/read operations, and forwards every unselected call.
        return f"""#!{sys.executable}
import json
import os
from pathlib import Path
import sys

arguments = sys.argv[1:]
command = next((arg for arg in arguments if arg in ("ls-files", "grep")), None)
is_rng = command == "grep" and "apps/mobile/lib" in arguments
selected = ({phase!r} == "enumeration" and command == "ls-files" or
            {phase!r} == "credentials" and command == "grep" and not is_rng or
            {phase!r} == "rng" and is_rng)
if selected:
    quiet = any(arg == "--quiet" or
                (arg.startswith("-") and not arg.startswith("--") and "q" in arg)
                for arg in arguments)
    Path({str(probe)!r}).write_text(json.dumps({{"quiet": quiet}}), encoding="utf-8")
    marker = {CANARY!r}
    if {partial!r}:
        print("config/serviceAccountSynthetic.json")
        print(marker)
    print(marker, file=sys.stderr)
    sys.exit({code!r})
os.execv({self.git!r}, [{self.git!r}, *arguments])
"""

    def assert_passes(self, result):
        self.assertTrue(result.returncode == 0, "Benign source scan should pass")
        self.assertTrue(PASS in result.stdout, "Successful scan omitted its PASS signal")
        self.assert_redacted(result)

    def assert_rejected(self, result):
        self.assertTrue(result.returncode != 0, "Unsafe or incomplete scan returned success")
        self.assertFalse(PASS in result.stdout + result.stderr,
                         "Failed scan must never announce PASS")
        self.assertTrue(bool((result.stdout + result.stderr).strip()),
                        "Failed scan must provide a sanitized diagnostic")
        self.assert_redacted(result)

    def assert_redacted(self, result, forbidden=()):
        output = result.stdout + result.stderr
        self.assertFalse(CANARY.encode() in output,
                         "Scanner exposed synthetic input/diagnostic content")
        self.assertFalse(any(value.encode() in output for value in forbidden),
                         "Scanner exposed a synthetic credential or private value")

    def test_clean_tracked_repository_passes(self):
        self.assert_passes(self.run_scan())

    def test_every_credential_pattern_family_is_rejected(self):
        fixtures = credential_fixtures()
        self.assertEqual(17, len(fixtures))
        for family, value in fixtures.items():
            with self.subTest(family=family):
                result = self.run_scan({"backend/service/lib/source.dart": marked(value)})
                self.assert_rejected(result)
                self.assert_redacted(result, (value,))

    def test_all_existing_executable_roots_are_scanned(self):
        value = credential_fixtures()["google-api"]
        for scope in ("apps", "packages", "backend", ".github"):
            with self.subTest(scope=scope):
                self.assert_rejected(self.run_scan({f"{scope}/source.txt": marked(value)}))

    def test_all_existing_private_rng_spellings_are_rejected(self):
        variants = ("rngSeed", "rng_seed", "futureDeckOrder", "future_deck_order",
                    "privateRngState", "private_rng_state")
        for variant in variants:
            with self.subTest(variant=variant):
                self.assert_rejected(self.run_scan({
                    "apps/mobile/lib/fixture.dart": marked(variant + " = synthetic;"),
                }))

    def test_all_forbidden_filename_families_remain_rejected(self):
        filenames = (".env", "config/.env.local", "serviceAccount.json",
                     "docs/serviceAccountSynthetic.json", "config/google-services.json",
                     "docs/GoogleService-Info.plist", "cert/key.p8", "test/cert.p12")
        for filename in filenames:
            with self.subTest(filename=filename):
                self.assert_rejected(self.run_scan({filename: marked("synthetic")}))

    def test_forbidden_filename_is_not_echoed_into_diagnostics(self):
        self.assert_rejected(self.run_scan({".env." + CANARY: b"synthetic\n"}))

    def test_early_forbidden_path_survives_a_listing_larger_than_a_pipe_buffer(self):
        # A real >64 KiB Git listing with an early hit protects against a
        # short-circuit grep/SIGPIPE turning a detection into pipeline failure.
        files = {".env": b"synthetic\n"}
        files.update({f"catalog/{index:04d}_" + "a" * 220: b"benign\n"
                      for index in range(400)})
        self.assertTrue(sum(len(path) + 1 for path in files) > 65536)
        self.assert_rejected(self.run_scan(files))

    def test_near_misses_do_not_broaden_credential_patterns(self):
        fixtures = {
            "short-google": "AI" + "za" + "a" * 34,
            "empty-oauth": "ya" + "29.",
            "short-github": "gh" + "p_" + "a" * 19,
            "short-slack": "xo" + "xb-" + "a" * 9,
            "public-key": " ".join(("-----BEGIN", "RSA", "PUBLIC", "KEY-----")),
            "similar-field": json.dumps({"private_key_hint": "synthetic"}),
            "case-sensitive-rng": "rngseed = synthetic",
        }
        for family, value in fixtures.items():
            with self.subTest(family=family):
                self.assert_passes(self.run_scan({"apps/mobile/lib/source.dart": marked(value)}))

    def test_documentation_tests_and_outside_scopes_stay_excluded(self):
        paths = ("apps/README.md", "backend/service/test/example.dart",
                 "packages/core/test/support/example.dart", "backend/test_generated.dart",
                 "docs/example.txt", "tool/fixture.txt")
        value = credential_fixtures()["github-p"]
        for path in paths:
            with self.subTest(path=path):
                self.assert_passes(self.run_scan({path: marked(value)}))

    def test_rng_guard_remains_limited_to_mobile_runtime(self):
        paths = ("apps/mobile/test/example.dart", "apps/other/lib/example.dart",
                 "packages/core/lib/example.dart", "backend/service/lib/example.dart",
                 ".github/source.txt")
        for path in paths:
            with self.subTest(path=path):
                self.assert_passes(self.run_scan({path: marked("rngSeed = synthetic")}))

    def test_untracked_inputs_remain_outside_the_source_scan(self):
        for kind, path, content in (
            ("credential", "backend/untracked.dart", marked(credential_fixtures()["oauth"])),
            ("rng", "apps/mobile/lib/untracked.dart", marked("rngSeed = synthetic")),
            ("filename", "untracked/.env", marked("synthetic")),
        ):
            with self.subTest(kind=kind):
                self.assert_passes(self.run_scan(untracked={path: content}))

    def test_binary_content_preserves_the_existing_skip(self):
        for kind, value in (("credential", credential_fixtures()["google-api"]),
                            ("rng", "rngSeed = synthetic")):
            with self.subTest(kind=kind):
                self.assert_passes(self.run_scan({
                    "apps/mobile/lib/fixture.bin": b"\x00" + marked(value),
                }))

    def test_similar_allowed_filenames_are_not_new_denials(self):
        filenames = (".environment", "example.env", "serviceAccount.txt",
                     "google-services.json.example", "GoogleService-Info.plist.example",
                     "cert/key.p12.example")
        for filename in filenames:
            with self.subTest(filename=filename):
                self.assert_passes(self.run_scan({filename: marked("synthetic")}))

    def test_tracked_working_tree_content_not_only_the_index_is_scanned(self):
        path = "backend/service/lib/source.dart"
        self.assert_rejected(self.run_scan(
            {path: b"benign\n"},
            replacements={path: marked(credential_fixtures()["google-api"])},
        ))

    def test_credential_diagnostics_never_echo_the_matched_line(self):
        value = credential_fixtures()["oauth"]
        result = self.run_scan({"backend/service/lib/source.dart": marked(value)})
        self.assert_rejected(result)
        self.assert_redacted(result, (value,))

    def test_rng_diagnostics_never_echo_adjacent_private_content(self):
        result = self.run_scan({
            "apps/mobile/lib/source.dart": marked("futureDeckOrder = synthetic"),
        })
        self.assert_rejected(result)

    def test_outside_git_is_an_incomplete_scan_not_a_pass(self):
        self.assert_rejected(self.run_scan(initialize=False))

    def test_real_unreadable_tracked_file_is_an_incomplete_scan(self):
        path = "backend/service/lib/unreadable.dart"
        self.assert_rejected(self.run_scan({path: marked("synthetic")}, unreadable=(path,)))

    def test_git_enumeration_errors_fail_closed_without_raw_diagnostics(self):
        self.check_git_failures("enumeration")

    def test_git_credential_search_errors_fail_closed_without_raw_diagnostics(self):
        self.check_git_failures("credentials")

    def test_git_rng_search_errors_fail_closed_without_raw_diagnostics(self):
        self.check_git_failures("rng")

    def check_git_failures(self, phase):
        # For ls-files, every nonzero status is an error. For grep, status 1
        # only means no matches when stderr is empty: unreadable files can
        # otherwise produce status 1 plus a diagnostic. Every stub adds one.
        for code in (1, 2, 129):
            for partial in (False, True):
                with self.subTest(phase=phase, code=code, partial=partial):
                    self.assert_rejected(self.run_scan(fault=(phase, code, partial)))


if __name__ == "__main__":
    unittest.main()
