"""Trello #89: toolchain, read-only CI, explicit formatting and drift regressions."""

from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


TOOL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))
import preflight


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="preflight fixture ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / ".fvmrc").write_text('{"flutter":"3.47.0"}', encoding="utf-8")
        self.env = patch.dict(os.environ, {"CI": "", "GITHUB_ACTIONS": ""})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.calls = []
        self.flutter = {"frameworkVersion": "3.47.0", "dartSdkVersion": "3.13.0"}
        self.dart_version = "Dart SDK version: 3.13.0 (stable) on fixture\n"
        self.exit_codes = {}

    def run_command(self, command, **kwargs):
        self.calls.append(command)
        self.assertEqual(self.root, kwargs["cwd"])
        stdout = ""
        if command == ["flutter", "--version", "--machine"]:
            stdout = json.dumps(self.flutter)
        elif command == ["dart", "--version"]:
            stdout = self.dart_version
        return subprocess.CompletedProcess(command, self.exit_codes.get(tuple(command), 0),
                                           stdout=stdout, stderr="")

    def run_preflight(self, **kwargs):
        with patch.object(preflight.subprocess, "run", side_effect=self.run_command), \
                redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            return preflight.preflight(self.root, **kwargs)

    def check_command(self):
        return ["dart", "format", "--output=none", "--set-exit-if-changed",
                "apps", "packages", "backend"]

    def test_format_stage_checks_both_executables_and_enforces_lockfile(self):
        self.assertEqual(0, self.run_preflight(format_only=True))
        self.assertEqual([
            ["flutter", "--version", "--machine"], ["dart", "--version"],
            ["flutter", "pub", "get", "--enforce-lockfile"], self.check_command(),
        ], self.calls)

    def test_default_runs_foundation_then_policy_and_artifact_checks(self):
        self.assertEqual(0, self.run_preflight())
        self.assertEqual([
            ["bash", str(self.root / "tool" / script)]
            for script in ("ci.sh", "check_ci_policy.sh", "scan_artifacts.sh")
        ], self.calls)

    def test_full_preflight_preserves_a_failing_gate_exit_code(self):
        for script in ("ci.sh", "check_ci_policy.sh", "scan_artifacts.sh"):
            with self.subTest(script=script):
                self.calls = []
                self.exit_codes = {("bash", str(self.root / "tool" / script)): 7}
                self.assertEqual(7, self.run_preflight())
                self.assertEqual(script, Path(self.calls[-1][1]).name)

    def test_explicit_local_format_still_runs_every_gate(self):
        self.assertEqual(0, self.run_preflight(format_local=True))
        self.assertIn(["dart", "format", "apps", "packages", "backend"], self.calls)
        self.assertEqual(["bash", str(self.root / "tool" / "scan_artifacts.sh")], self.calls[-1])

    def test_format_is_rejected_in_CI_even_if_the_other_flag_is_false(self):
        for env in ({"CI": "true"}, {"CI": "1"}, {"CI": "false", "GITHUB_ACTIONS": "true"}):
            with self.subTest(env=env), patch.dict(os.environ, env):
                with self.assertRaisesRegex(preflight.PreflightError, "forbidden in CI"):
                    self.run_preflight(format_local=True, format_only=True)
                self.assertEqual([], self.calls)

    def test_wrong_flutter_or_bundled_dart_fails_before_mutation(self):
        for field, version in (("frameworkVersion", "3.46.0"), ("dartSdkVersion", "3.12.0")):
            with self.subTest(field=field):
                self.calls = []
                self.flutter = {"frameworkVersion": "3.47.0", "dartSdkVersion": "3.13.0"}
                self.flutter[field] = version
                with self.assertRaises(preflight.PreflightError):
                    self.run_preflight(format_local=True)
                self.assertFalse(any("pub" in call or "format" in call for call in self.calls))

    def test_mixed_PATH_or_prerelease_dart_is_rejected(self):
        for version in ("3.12.0", "3.13.0-1.0.dev", "unknown"):
            with self.subTest(version=version):
                self.dart_version = f"Dart SDK version: {version} (fixture)\n"
                with self.assertRaises(preflight.PreflightError):
                    self.run_preflight(format_only=True)

    def test_non_exact_flutter_pin_is_rejected_before_running_commands(self):
        (self.root / ".fvmrc").write_text('{"flutter":"stable"}', encoding="utf-8")
        with self.assertRaisesRegex(preflight.PreflightError, "exact Flutter version"):
            self.run_preflight(format_only=True)
        self.assertEqual([], self.calls)

    def test_dependency_failure_prevents_formatting(self):
        self.exit_codes[("flutter", "pub", "get", "--enforce-lockfile")] = 9
        self.assertEqual(9, self.run_preflight(format_local=True))
        self.assertFalse(any("format" in call for call in self.calls))

    def test_formatter_failure_stops_before_other_gates(self):
        for write in (False, True):
            with self.subTest(write=write):
                command = ["dart", "format", "apps", "packages", "backend"] if write else self.check_command()
                self.exit_codes = {tuple(command): 1}
                self.calls = []
                self.assertEqual(1, self.run_preflight(format_local=write, format_only=True))
                self.assertEqual(command, self.calls[-1])

    def test_main_reports_missing_or_malformed_toolchain_without_traceback(self):
        for error in (FileNotFoundError(2, "missing", "flutter"), ValueError("bad JSON"),
                      subprocess.CalledProcessError(1, ["dart", "--version"])):
            with self.subTest(error=type(error)), patch.object(preflight, "preflight", side_effect=error):
                output = io.StringIO()
                with redirect_stderr(output):
                    self.assertEqual(1, preflight.main(["--format-only"]))
                self.assertIn("Preflight blocked:", output.getvalue())
                self.assertNotIn("Traceback", output.getvalue())

    def test_foundation_and_PR_review_use_the_same_readonly_stage(self):
        stage = "python3 -B tool/preflight.py --format-only"
        ci = (TOOL / "ci.sh").read_text(encoding="utf-8")
        review = (TOOL.parent / ".github/workflows/pr-review.yml").read_text(encoding="utf-8")
        self.assertIn(stage, ci)
        self.assertIn(stage, review)
        self.assertNotIn("dart format apps packages backend", ci)


@unittest.skipUnless(shutil.which("flutter") and shutil.which("dart"),
                     "real formatter fixture requires the pinned Flutter/Dart on PATH")
class RealFormatterTests(unittest.TestCase):
    def test_real_CLI_rejects_drift_preserves_bytes_and_formats_only_explicitly(self):
        with tempfile.TemporaryDirectory(prefix="preflight real fixture ") as folder:
            root = Path(folder)
            (root / "tool").mkdir()
            shutil.copyfile(TOOL / "preflight.py", root / "tool/preflight.py")
            shutil.copyfile(TOOL.parent / ".fvmrc", root / ".fvmrc")
            (root / "pubspec.yaml").write_text(
                "name: preflight_fixture\nenvironment:\n  sdk: ^3.13.0\n", encoding="utf-8")
            config = root / "flutter-config"
            config.mkdir()
            env = {**os.environ, "CI": "", "GITHUB_ACTIONS": "",
                   "XDG_CONFIG_HOME": str(config), "FLUTTER_SUPPRESS_ANALYTICS": "true"}
            # Dependency-free fixture; prepare a lockfile without using the network.
            setup = subprocess.run(["flutter", "pub", "get", "--offline"], cwd=root,
                                   env=env, capture_output=True, text=True, timeout=60)
            self.assertEqual(0, setup.returncode, setup.stdout + setup.stderr)
            original = b"void main(){print('preflight');}\n"
            canonical = b"void main() {\n  print('preflight');\n}\n"
            files = []
            for directory in preflight.SOURCE_ROOTS:
                (root / directory).mkdir()
                path = root / directory / "fixture.dart"
                path.write_bytes(original)
                files.append(path)

            def run(*args, ci=False):
                return subprocess.run([sys.executable, "-B", "tool/preflight.py", *args],
                                      cwd=root, env={**env, "CI": "true" if ci else ""},
                                      capture_output=True, text=True, timeout=60)

            result = run("--format-only", ci=True)
            self.assertEqual(1, result.returncode, result.stdout + result.stderr)
            self.assertIn("Formatting drift", result.stderr)
            self.assertTrue(all(path.read_bytes() == original for path in files))
            result = run("--format", "--format-only", ci=True)
            self.assertEqual(1, result.returncode)
            self.assertIn("forbidden in CI", result.stderr)
            self.assertTrue(all(path.read_bytes() == original for path in files))

            result = run("--format", "--format-only")
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertTrue(all(path.read_bytes() == canonical for path in files))
            result = run("--format-only", ci=True)
            self.assertEqual(0, result.returncode, result.stdout + result.stderr)
            self.assertTrue(all(path.read_bytes() == canonical for path in files))

            files[-1].write_bytes(original)  # Drift after a successful preflight.
            result = run("--format-only", ci=True)
            self.assertEqual(1, result.returncode, result.stdout + result.stderr)
            self.assertEqual(original, files[-1].read_bytes())
            self.assertTrue(all(path.read_bytes() == canonical for path in files[:-1]))


if __name__ == "__main__":
    unittest.main()
