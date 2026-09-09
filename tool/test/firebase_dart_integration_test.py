"""Offline regressions: an exit-0/skipped Dart suite must never pass the gate."""

from contextlib import redirect_stderr, redirect_stdout
from copy import deepcopy
import io
import json
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch


TOOL = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))
import firebase_dart_integration as gate


def success_events():
    events = [{"type": "start", "protocolVersion": "0.1.1"}]
    next_test = 1
    for suite_id, (path, names) in enumerate(gate.REQUIRED.items()):
        events.append({"type": "suite", "suite": {"id": suite_id, "path": path}})
        for name, hidden in [("loading", True), *((name, False) for name in names)]:
            events.append({"type": "testStart", "test": {
                "id": next_test, "name": name, "suiteID": suite_id,
                "metadata": {"skip": False}}})
            events.append({"type": "testDone", "testID": next_test,
                           "result": "success", "skipped": False, "hidden": hidden})
            next_test += 1
    return [*events, {"type": "done", "success": True}]


def report(events):
    return "\n".join(json.dumps(event) for event in events)


class DartFirebaseGateTests(unittest.TestCase):
    def setUp(self):
        self.events = success_events()
        self.env = {"GCLOUD_PROJECT": gate.PROJECT,
                    "FIRESTORE_EMULATOR_HOST": "127.0.0.1:8080",
                    "FIREBASE_AUTH_EMULATOR_HOST": "127.0.0.1:9099"}

    def test_success_requires_three_visible_tests_not_suite_loading(self):
        self.assertEqual(3, gate.validate_report(report(self.events)))

    def test_done_success_and_zero_exit_do_not_excuse_any_skipped_test(self):
        for index, event in enumerate(self.events):
            if event["type"] != "testDone":
                continue
            with self.subTest(index=index):
                events = deepcopy(self.events)
                events[index]["skipped"] = True
                with self.assertRaisesRegex(gate.IntegrationGateError, "failedOrSkippedTest"):
                    gate.validate_report(report(events))

    def test_late_error_after_successful_completion_still_fails(self):
        self.events.insert(-1, {"type": "error", "testID": 2, "error": "private-canary"})
        with self.assertRaisesRegex(gate.IntegrationGateError, "testError"):
            gate.validate_report(report(self.events))

    def test_missing_renamed_wrong_file_or_hidden_required_test_fails(self):
        for mutation in ("missing", "renamed", "wrongFile", "hidden"):
            with self.subTest(mutation=mutation):
                events = deepcopy(self.events)
                if mutation == "missing":
                    events = [e for e in events if not (
                        e.get("testID") == 2 or e.get("test", {}).get("id") == 2)]
                elif mutation == "renamed":
                    next(e["test"] for e in events if e.get("test", {}).get("id") == 2)["name"] = "other"
                elif mutation == "wrongFile":
                    next(e["suite"] for e in events if e["type"] == "suite")["path"] = "other.dart"
                else:
                    next(e for e in events if e.get("testID") == 2)["hidden"] = True
                with self.assertRaisesRegex(gate.IntegrationGateError, "requiredTestsNotExecuted"):
                    gate.validate_report(report(events))

    def test_incomplete_malformed_or_unsupported_report_fails(self):
        for output in ("", "not JSON", "[]", report(self.events[:-1]),
                       report([*self.events[:-1], {"type": "done", "success": None}]),
                       report([{**self.events[0], "protocolVersion": "2"}, *self.events[1:]])):
            with self.subTest(output=output[:25]), self.assertRaises(gate.IntegrationGateError):
                gate.validate_report(output)

    def test_failed_test_and_incomplete_completion_fail(self):
        for mutation in ("failure", "error", "missing", "noHidden", "noSkipped"):
            with self.subTest(mutation=mutation):
                events = deepcopy(self.events)
                done = next(e for e in events if e.get("testID") == 2)
                if mutation == "missing":
                    events.remove(done)
                elif mutation == "noHidden":
                    done.pop("hidden")
                elif mutation == "noSkipped":
                    done.pop("skipped")
                else:
                    done["result"] = mutation
                with self.assertRaises(gate.IntegrationGateError):
                    gate.validate_report(report(events))

    def test_repeated_boundaries_ids_or_completions_fail(self):
        for kind in ("start", "done", "suite", "testStart", "testDone"):
            events = deepcopy(self.events)
            event = next(e for e in events if e["type"] == kind)
            events.insert(-1, deepcopy(event))
            with self.subTest(kind=kind), self.assertRaises(gate.IntegrationGateError):
                gate.validate_report(report(events))

    def test_duplicate_visible_identity_under_different_id_fails(self):
        start = deepcopy(next(e for e in self.events if e.get("test", {}).get("id") == 2))
        start["test"]["id"] = 99
        done = deepcopy(next(e for e in self.events if e.get("testID") == 2))
        done["testID"] = 99
        self.events[-1:-1] = [start, done]
        with self.assertRaisesRegex(gate.IntegrationGateError, "duplicateTestIdentity"):
            gate.validate_report(report(self.events))

    def test_unrelated_protocol_events_and_interleaved_suites_are_supported(self):
        events = [self.events[0]]
        for kind in ("suite", "testStart", "testDone"):
            events.extend(e for e in self.events if e["type"] == kind)
        events.insert(2, {"type": "group", "group": {}})
        events.insert(3, {"type": "print", "messageType": "skip", "message": "not authoritative"})
        events.append(self.events[-1])
        self.assertEqual(3, gate.validate_report(report(events)))

    def test_missing_nonloopback_or_invalid_port_fails_before_starting_dart(self):
        for key in self.env:
            values = ("", "real-project") if key == "GCLOUD_PROJECT" else (
                "", "localhost:8080", "0.0.0.0:8080", "example.com:8080",
                "127.0.0.1:0", "127.0.0.1:65536", "127.0.0.1:8080/path",
                "http://127.0.0.1:8080", "127.0.0.1:8080\n")
            for value in values:
                with self.subTest(key=key, value=value), patch.object(gate.subprocess, "run") as run:
                    with self.assertRaises(gate.IntegrationGateError):
                        gate.run_gate(TOOL.parent, {**self.env, key: value})
                    run.assert_not_called()

    def test_runner_uses_fixed_test_paths_no_shell_and_safe_success_summary(self):
        result = subprocess.CompletedProcess([], 0, stdout=report(self.events), stderr="private-canary")
        output = io.StringIO()
        with patch.object(gate.subprocess, "run", return_value=result) as run, redirect_stdout(output):
            gate.run_gate(TOOL.parent, self.env)
        args, kwargs = run.call_args
        self.assertEqual(["dart", "test", "--reporter=json", "--concurrency=1", *gate.REQUIRED], args[0])
        self.assertEqual(TOOL.parent / "backend" / "command_service", kwargs["cwd"])
        self.assertNotIn("shell", kwargs)
        self.assertEqual(180, kwargs["timeout"])
        self.assertIn("PASS (3 tests, 0 skipped)", output.getvalue())
        self.assertNotIn("private-canary", output.getvalue())

    def test_nonzero_dart_exit_fails_even_with_successful_json(self):
        result = subprocess.CompletedProcess([], 7, stdout=report(self.events), stderr="private-canary")
        with patch.object(gate.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(gate.IntegrationGateError, "dartTestsFailed"):
                gate.run_gate(TOOL.parent, self.env)

    def test_main_failure_and_timeout_are_nonzero_without_raw_output(self):
        for error in (gate.IntegrationGateError("testError"), OSError("private-canary"),
                      subprocess.TimeoutExpired(["dart"], 180, output="private-canary")):
            output = io.StringIO()
            with patch.object(gate, "run_gate", side_effect=error), redirect_stderr(output):
                self.assertEqual(1, gate.main())
            self.assertIn("FAIL", output.getvalue())
            self.assertNotIn("private-canary", output.getvalue())

    def test_required_ci_job_runs_both_suites_with_pinned_flutter(self):
        scripts = json.loads((TOOL / "firebase" / "package.json").read_text())["scripts"]
        self.assertEqual("npm test && python3 ../firebase_dart_integration.py", scripts["test:all"])
        self.assertIn('--project demo-board-game-local --only auth,firestore "npm run test:all"',
                      scripts["emulators:test:all"])
        self.assertIn('--project demo-board-game-local --only auth,firestore "npm test"',
                      scripts["emulators:test"])
        workflow = (TOOL.parent / ".github/workflows/ci.yml").read_text()
        job = workflow.split("  firebase-emulators:", 1)[1].split("  android-tier1:", 1)[0]
        pin = json.loads((TOOL.parent / ".fvmrc").read_text())["flutter"]
        self.assertIn(f"flutter-version: '{pin}'", job)
        self.assertIn("flutter pub get --enforce-lockfile", job)
        self.assertIn("run: npm run emulators:test:all", job)
        self.assertNotIn("continue-on-error", job)


if __name__ == "__main__":
    unittest.main()
