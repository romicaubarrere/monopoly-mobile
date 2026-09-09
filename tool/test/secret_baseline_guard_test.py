"""Offline baseline policy tests; no detect-secrets dependency in Foundation."""

from contextlib import redirect_stderr
from copy import deepcopy
import hashlib
import hmac
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tool"))
import secret_baseline_guard as guard


def public_test_value(message):
    # Deterministic public test recipe, not a credential or another literal
    # high-entropy exception committed alongside the scanner tests.
    return hmac.new(b"public scanner regression fixture", message, hashlib.sha256).hexdigest()


class SecretBaselineGuardTests(unittest.TestCase):
    def test_required_job_installs_detector_in_venv_visible_to_isolated_python(self):
        workflow = (ROOT / ".github/workflows/pr-review.yml").read_text(encoding="utf-8")
        job = workflow.split("  secret-review:", 1)[1].split("  dependency-review:", 1)[0]
        install = job.split("      - name: Install detect-secrets", 1)[1].split(
            "      - name: Validate the audited public-fixture baseline", 1)[0]
        # User-site installs disappear under the guard's intentional Python -I.
        # Keep install, isolated import smoke, and later steps on one interpreter.
        self.assertIn('mktemp -d "${RUNNER_TEMP}/detect-secrets.XXXXXX"', install)
        self.assertIn('python -m venv "${secret_venv}"', install)
        self.assertIn('"${secret_venv}/bin/python" -m pip install', install)
        self.assertIn("'detect-secrets==1.5.0'", install)
        self.assertIn('"${secret_venv}/bin/python" -I -B -c', install)
        self.assertIn('"${secret_venv}/bin" >> "${GITHUB_PATH}"', install)
        self.assertNotIn("--user", install)
        self.assertNotIn("--system-site-packages", install)
        self.assertNotIn("continue-on-error", job)

    def setUp(self):
        self.baseline = guard.decode((ROOT / guard.BASELINE).read_text(encoding="utf-8"))
        self.report_text = (ROOT / guard.REPORT).read_text(encoding="utf-8")
        self.fixtures = {
            name: guard.decode((ROOT / guard.FIXTURES / name).read_text(encoding="utf-8"))
            for name in guard.PUBLIC_PATHS
        }
        # Unit tests mutate candidates against an unchanged settings reference.
        # The required real-hook suite separately checks the installed defaults.
        self.defaults = {key: deepcopy(self.baseline[key]) for key in (
            "version", "plugins_used", "filters_used")}

    def validate(self):
        return guard.validate(self.baseline, self.report_text, self.fixtures, self.defaults)

    def test_all_16_occurrences_have_14_exact_audited_baseline_identities(self):
        before = deepcopy((self.baseline, self.fixtures))
        self.assertEqual({"publicSnapshotOccurrences": 16, "approvedHashIdentities": 14},
                         self.validate())
        self.assertEqual(before, (self.baseline, self.fixtures))
        self.assertEqual(guard.decode(self.report_text), guard.expected_report(self.fixtures))

    def test_missing_extra_renamed_and_duplicate_baseline_entries_fail(self):
        original = deepcopy(self.baseline)
        for mutation in (
                lambda entries: entries.pop(),
                lambda entries: entries.append(deepcopy(entries[0])),
                lambda entries: entries[0].update(filename="another.json"),
                lambda entries: entries[0].update(type="Secret Keyword"),
                lambda entries: entries[0].update(hashed_secret=public_test_value(b"extra")[:40]),
                lambda entries: entries[0].update(extra="not allowed")):
            self.baseline = deepcopy(original)
            mutation(self.baseline["results"][guard.REPORT])
            with self.subTest(mutation=mutation), self.assertRaisesRegex(
                    guard.GuardError, "unapprovedBaselineEntry"):
                self.validate()

    def test_additional_filename_even_without_entries_is_rejected(self):
        self.baseline["results"]["another.json"] = []
        with self.assertRaisesRegex(guard.GuardError, "unapprovedBaselineEntry"):
            self.validate()

    def test_unverified_does_not_mean_audited_false_positive(self):
        entry = self.baseline["results"][guard.REPORT][0]
        for key, value in (("is_secret", True), ("is_secret", 0),
                           ("is_verified", True), ("is_verified", 0)):
            with self.subTest(key=key, value=value):
                entry[key] = value
                with self.assertRaisesRegex(guard.GuardError, "unapprovedBaselineEntry"):
                    self.validate()
                entry[key] = False
        del entry["is_secret"]
        with self.assertRaisesRegex(guard.GuardError, "unapprovedBaselineEntry"):
            self.validate()

    def test_wrong_missing_or_boolean_line_number_is_rejected(self):
        entry = self.baseline["results"][guard.REPORT][0]
        for value in (1, True, 10.0):
            entry["line_number"] = value
            with self.subTest(value=value), self.assertRaisesRegex(
                    guard.GuardError, "unapprovedBaselineEntry"):
                self.validate()
        del entry["line_number"]
        with self.assertRaisesRegex(guard.GuardError, "unapprovedBaselineEntry"):
            self.validate()

    def test_removed_plugin_or_higher_entropy_limit_is_rejected(self):
        plugins = deepcopy(self.baseline["plugins_used"])
        self.baseline["plugins_used"] = plugins[:-1]
        with self.assertRaisesRegex(guard.GuardError, "nonDefaultDetectorSettings"):
            self.validate()
        self.baseline["plugins_used"] = plugins
        for plugin in plugins:
            if plugin["name"] == "HexHighEntropyString":
                plugin["limit"] = 5.0
        with self.assertRaisesRegex(guard.GuardError, "nonDefaultDetectorSettings"):
            self.validate()

    def test_missing_settings_custom_plugins_and_filters_are_rejected_without_imports(self):
        original = deepcopy(self.baseline)
        for key, replacement in (
                ("plugins_used", []),
                ("plugins_used", [{"name": "Custom", "path": "file://never-import.py"}]),
                ("filters_used", []),
                ("filters_used", [{"path": "file://never-import.py::exclude"}]),
                ("filters_used", [{"path": "detect_secrets.filters.regex.should_exclude_files",
                                   "pattern": ".*"}])):
            self.baseline = deepcopy(original)
            self.baseline[key] = replacement
            with self.subTest(key=key, replacement=replacement), self.assertRaisesRegex(
                    guard.GuardError, "nonDefaultDetectorSettings"):
                self.validate()
        del self.baseline["plugins_used"]
        with self.assertRaisesRegex(guard.GuardError, "invalidBaselineSchema"):
            self.validate()

    def test_closed_baseline_schema_and_version(self):
        original = deepcopy(self.baseline)
        for key, value in (("version", "1.4.0"), ("generated_at", "arbitrary material"),
                           ("generated_at", None), ("credential", "not permitted"),
                           ("exclude", {"files": ".*"})):
            self.baseline = {**original, key: value}
            with self.subTest(key=key), self.assertRaisesRegex(
                    guard.GuardError, "invalidBaselineSchema"):
                self.validate()

    def test_golden_new_field_or_hash_change_is_not_self_approving(self):
        original = guard.decode(self.report_text)
        for mutate in (
                lambda value: value.update(password=public_test_value(b"new credential")),
                lambda value: value["snapshots"][0].update(sha256=public_test_value(b"new hash")),
                lambda value: value["snapshots"][0].update(serializedSnapshotBytes=True),
                lambda value: value["snapshots"].pop()):
            report = deepcopy(original)
            mutate(report)
            self.report_text = json.dumps(report, indent=2) + "\n"
            with self.assertRaisesRegex(guard.GuardError, "publicSnapshotReportMismatch"):
                self.validate()

    def test_source_change_and_regenerated_report_still_require_baseline_review(self):
        self.fixtures["bankruptcy_plans.json"]["declareA"]["stateAfter"]["gameId"] += "-changed"
        self.report_text = json.dumps(guard.expected_report(self.fixtures), indent=2) + "\n"
        with self.assertRaisesRegex(guard.GuardError, "unapprovedBaselineEntry"):
            self.validate()

    def test_declared_hash_and_baseline_changed_together_cannot_fake_source_provenance(self):
        new_hash = public_test_value(b"invented snapshot")
        report = guard.decode(self.report_text)
        report["snapshots"][0]["sha256"] = new_hash
        self.report_text = json.dumps(report, indent=2) + "\n"
        self.baseline["results"][guard.REPORT][0]["hashed_secret"] = hashlib.sha1(
            new_hash.encode("utf-8")).hexdigest()
        with self.assertRaisesRegex(guard.GuardError, "publicSnapshotReportMismatch"):
            self.validate()

    def test_source_missing_or_non_public_fails_closed(self):
        del self.fixtures["bankruptcy_plans.json"]["declareA"]["initialState"]
        with self.assertRaisesRegex(guard.GuardError, "missingPublicSnapshot"):
            self.validate()
        self.setUp()
        self.fixtures["bankruptcy_plans.json"]["declareA"]["initialState"]["nested"] = [
            {"ToKeN": "private synthetic material"}]
        with self.assertRaisesRegex(guard.GuardError, "nonPublicSnapshot"):
            self.validate()

    def test_snapshot_numbers_metadata_and_unsupported_values(self):
        good = {"schemaVersion": 1, "stateVersion": 0, "gameId": "public"}
        for key, value in (("schemaVersion", True), ("schemaVersion", 2),
                           ("stateVersion", False), ("stateVersion", -1), ("gameId", "")):
            with self.subTest(key=key), self.assertRaisesRegex(
                    guard.GuardError, "invalidPublicSnapshot"):
                guard.snapshot_bytes({**good, key: value})
        with self.assertRaisesRegex(guard.GuardError, "nonIntegerSnapshotJson"):
            guard.snapshot_bytes({**good, "amount": 0.5})

    def test_utf8_escaping_and_dart_utf16_key_order_are_explicit(self):
        state = {"schemaVersion": 1, "stateVersion": 0, "gameId": "ñ🎲\n\"",
                 "\ue000": 2, "\U00010000": 1}
        expected = ('{"gameId":"ñ🎲\\n\\\"","schemaVersion":1,"stateVersion":0,'
                    '"\U00010000":1,"\ue000":2}').encode("utf-8")
        self.assertEqual(expected, guard.snapshot_bytes(state))

    def test_duplicate_json_keys_non_finite_numbers_and_comments_fail(self):
        for text in ('{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}',
                     '{"x":1 // not JSON\n}'):
            with self.subTest(text=text), self.assertRaises(guard.GuardError):
                guard.decode(text)

    def test_CLI_rejects_arguments_without_echoing_them(self):
        output = io.StringIO()
        with redirect_stderr(output), patch.object(guard, "pinned_defaults") as defaults:
            self.assertEqual(64, guard.main(["private argument"]))
        defaults.assert_not_called()
        self.assertNotIn("private argument", output.getvalue())

    def test_CLI_missing_detector_is_redacted_and_fails_closed(self):
        output = io.StringIO()
        with redirect_stderr(output), patch.object(guard.subprocess, "run",
                                                   side_effect=OSError("private path")):
            self.assertEqual(1, guard.main([]))
        self.assertEqual("Secret baseline rejected: pinnedDetectorUnavailable\n", output.getvalue())

    def test_clean_default_process_never_receives_baseline_contents(self):
        completed = type("Completed", (), {"stdout": json.dumps(self.defaults)})()
        with patch.object(guard.subprocess, "run", return_value=completed) as run:
            self.assertEqual(self.defaults, guard.pinned_defaults())
        command = run.call_args.args[0]
        self.assertEqual([sys.executable, "-I", "-B", "-c"], command[:4])
        self.assertNotIn(guard.BASELINE, command[4])
        self.assertNotIn("baseline.load", command[4])
        self.assertTrue(run.call_args.kwargs["check"])
        self.assertEqual(30, run.call_args.kwargs["timeout"])


if __name__ == "__main__":
    unittest.main()
