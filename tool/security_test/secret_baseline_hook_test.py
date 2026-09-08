"""Required real detect-secrets 1.5.0 regression tests; never skip if missing.

Run in security / changed-secrets after its existing pinned pip install. All
mutations are isolated in temporary Git repositories, never the real checkout.
"""

import hashlib
import hmac
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))
import secret_baseline_guard as guard


def public_test_value(message):
    return hmac.new(b"public scanner regression fixture", message, hashlib.sha256).hexdigest()


class SecretBaselineHookTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Deliberately required: missing/wrong detector is an error, not a skip.
        cls.defaults = guard.pinned_defaults()

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="secret-baseline-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        paths = [guard.BASELINE, guard.REPORT, "tool/secret_baseline_guard.py"]
        paths += [guard.FIXTURES + "/" + name for name in guard.PUBLIC_PATHS]
        for relative in paths:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)
        self.git("init", "--quiet")
        self.git("add", "--", *paths)

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, check=True,
                              capture_output=True, text=True, timeout=30)

    def hook(self, *files):
        return subprocess.run(
            [sys.executable, "-I", "-B", "-m", "detect_secrets.pre_commit_hook",
             "--baseline", guard.BASELINE, "--", *files],
            cwd=self.root, capture_output=True, text=True, timeout=30)

    def cli(self):
        return subprocess.run([sys.executable, "-I", "-B", "tool/secret_baseline_guard.py"],
                              cwd=self.root, capture_output=True, text=True, timeout=30)

    def write_report(self, report):
        (self.root / guard.REPORT).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    def report(self):
        return json.loads((self.root / guard.REPORT).read_text(encoding="utf-8"))

    def test_installed_defaults_guard_and_real_hook_accept_only_the_approved_golden(self):
        before = (self.root / guard.BASELINE).read_bytes()
        result = self.cli()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual({"publicSnapshotOccurrences": 16, "approvedHashIdentities": 14},
                         json.loads(result.stdout))
        self.assertEqual("", result.stderr)
        # Include the baseline itself, as the changed-files job does on this PR.
        result = self.hook(guard.REPORT, guard.BASELINE)
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(before, (self.root / guard.BASELINE).read_bytes())

    def test_new_credential_in_the_same_JSON_still_fails_real_hook(self):
        report = self.report()
        report["password"] = public_test_value(b"new credential")
        self.write_report(report)
        result = self.hook(guard.REPORT)
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn(guard.REPORT, result.stdout)
        self.assertEqual(1, self.cli().returncode)

    def test_changed_hash_in_the_same_field_still_fails_real_hook(self):
        report = self.report()
        report["snapshots"][1]["sha256"] = public_test_value(b"unapproved hash")
        self.write_report(report)
        result = self.hook(guard.REPORT)
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn("Hex High Entropy String", result.stdout)
        self.assertEqual(1, self.cli().returncode)

    def test_approved_value_in_another_file_is_not_exempt(self):
        other = "other.json"
        (self.root / other).write_text(json.dumps({"sha256": self.report()["snapshots"][0]["sha256"]}),
                                      encoding="utf-8")
        result = self.hook(other)
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn(other, result.stdout)

    def test_known_hash_reused_as_credential_is_not_exempt_from_keyword_detector(self):
        report = self.report()
        report["password"] = report["snapshots"][0]["sha256"]
        self.write_report(report)
        result = self.hook(guard.REPORT)
        self.assertEqual(1, result.returncode, result.stdout + result.stderr)
        self.assertIn("Secret Keyword", result.stdout)
        self.assertEqual(1, self.cli().returncode)

    def test_baseline_line_rewrite_remains_a_failure_not_automatic_approval(self):
        baseline_file = self.root / guard.BASELINE
        baseline = json.loads(baseline_file.read_text(encoding="utf-8"))
        baseline["results"][guard.REPORT][0]["line_number"] += 1
        baseline_file.write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
        self.git("add", "--", guard.BASELINE)
        self.assertEqual(1, self.cli().returncode)
        result = self.hook(guard.REPORT)
        self.assertEqual(3, result.returncode, result.stdout + result.stderr)
        self.assertIn("baseline file was updated", result.stdout)

    def test_extra_exception_is_rejected_before_hook_can_ignore_it(self):
        baseline_file = self.root / guard.BASELINE
        baseline = json.loads(baseline_file.read_text(encoding="utf-8"))
        entry = dict(baseline["results"][guard.REPORT][0])
        entry["hashed_secret"] = hashlib.sha1(public_test_value(b"extra").encode("utf-8")).hexdigest()
        baseline["results"][guard.REPORT].append(entry)
        baseline_file.write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
        result = self.cli()
        self.assertEqual(1, result.returncode)
        self.assertIn("unapprovedBaselineEntry", result.stderr)
        self.assertEqual("", result.stdout)

    def test_custom_filter_is_rejected_without_import_or_side_effect(self):
        sentinel = self.root / "unexpected-import"
        module = self.root / "custom_filter.py"
        module.write_text("from pathlib import Path\nPath('unexpected-import').touch()\n"
                          "def exclude(**kwargs): return True\n", encoding="utf-8")
        baseline_file = self.root / guard.BASELINE
        baseline = json.loads(baseline_file.read_text(encoding="utf-8"))
        baseline["filters_used"].append({"path": "file://custom_filter.py::exclude"})
        baseline_file.write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
        result = self.cli()
        self.assertEqual(1, result.returncode)
        self.assertIn("nonDefaultDetectorSettings", result.stderr)
        self.assertFalse(sentinel.exists())

    def test_weakened_default_plugin_configuration_is_rejected(self):
        baseline_file = self.root / guard.BASELINE
        baseline = json.loads(baseline_file.read_text(encoding="utf-8"))
        baseline["plugins_used"] = [plugin for plugin in baseline["plugins_used"]
                                    if plugin["name"] != "KeywordDetector"]
        baseline_file.write_text(json.dumps(baseline, indent=2) + "\n", encoding="utf-8")
        result = self.cli()
        self.assertEqual(1, result.returncode)
        self.assertIn("nonDefaultDetectorSettings", result.stderr)


if __name__ == "__main__":
    unittest.main()
