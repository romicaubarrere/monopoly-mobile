#!/usr/bin/env python3
"""Trello #13: require actual Dart integration execution inside local emulators."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys


PROJECT = "demo-board-game-local"
REQUIRED = {
    "test/first_playable_firestore_rest_store_emulator_test.dart": (
        "Emulator admin credential is restricted to numeric loopback",
        "Dart store persists room/start/game and lost-ACK on Firestore Emulator",
    ),
    "test/first_playable_http_firestore_vertical_emulator_test.dart": (
        "Flutter wire crosses Auth, HTTP, Authority and Firestore for VP0",
    ),
}


class IntegrationGateError(Exception):
    """Safe failure code: never includes environment values or test payloads."""


def verify_environment(env):
    if env.get("GCLOUD_PROJECT") != PROJECT:
        raise IntegrationGateError("demoProjectRequired")
    for key in ("FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"):
        match = re.fullmatch(r"127\.0\.0\.1:([0-9]{1,5})", env.get(key, ""))
        if match is None or not 1 <= int(match[1]) <= 65535:
            raise IntegrationGateError("numericLoopbackEmulatorsRequired")


def validate_report(output):
    """Use testDone.skipped, not exit 0 or DoneEvent.success (both allow skips).

    Implements the pinned package:test JSON protocol, including errors emitted
    after a successful testDone. Suite loading is hidden and is not test proof.
    Required path/name pairs are deliberate acceptance identifiers: update them
    with the test when renaming a gate; do not silently accept missing coverage.
    """
    try:
        events = [json.loads(line) for line in output.splitlines() if line.strip()]
    except (TypeError, ValueError):
        raise IntegrationGateError("invalidReporterJson") from None
    if (not events or any(not isinstance(event, dict) for event in events)
            or events[0].get("type") != "start"
            or events[0].get("protocolVersion") != "0.1.1"
            or events[-1].get("type") != "done"
            or events[-1].get("success") is not True):
        raise IntegrationGateError("incompleteOrUnsupportedReport")

    suites, started, completed, executed = {}, {}, set(), set()
    for index, event in enumerate(events):
        kind = event.get("type")
        if kind == "error":
            raise IntegrationGateError("testError")
        if kind == "start" and index != 0 or kind == "done" and index != len(events) - 1:
            raise IntegrationGateError("invalidReportBoundary")
        if kind == "suite":
            suite = event.get("suite")
            if (not isinstance(suite, dict) or type(suite.get("id")) is not int
                    or not isinstance(suite.get("path"), str) or suite["id"] in suites):
                raise IntegrationGateError("invalidSuite")
            suites[suite["id"]] = suite["path"]
        elif kind == "testStart":
            test = event.get("test")
            if (not isinstance(test, dict) or type(test.get("id")) is not int
                    or type(test.get("suiteID")) is not int
                    or test["suiteID"] not in suites
                    or not isinstance(test.get("name"), str) or test["id"] in started):
                raise IntegrationGateError("invalidTestStart")
            started[test["id"]] = (suites[test["suiteID"]], test["name"])
        elif kind == "testDone":
            test_id = event.get("testID")
            if type(test_id) is not int or test_id not in started or test_id in completed:
                raise IntegrationGateError("invalidTestCompletion")
            if event.get("skipped") is not False or event.get("result") != "success":
                raise IntegrationGateError("failedOrSkippedTest")
            if type(event.get("hidden")) is not bool:
                raise IntegrationGateError("invalidHiddenStatus")
            completed.add(test_id)
            if not event["hidden"]:
                identity = started[test_id]
                if identity in executed:
                    raise IntegrationGateError("duplicateTestIdentity")
                executed.add(identity)
    required = {(path, name) for path, names in REQUIRED.items() for name in names}
    if set(started) != completed or not required.issubset(executed):
        raise IntegrationGateError("requiredTestsNotExecuted")
    return len(executed)


def run_gate(root, env):
    verify_environment(env)
    # No shell, client-selected test filters, fresh dependencies or source edits.
    result = subprocess.run(
        ["dart", "test", "--reporter=json", "--concurrency=1", *REQUIRED],
        cwd=root / "backend" / "command_service", env=env,
        capture_output=True, text=True, timeout=180,
    )
    if result.returncode != 0:
        raise IntegrationGateError("dartTestsFailed")
    count = validate_report(result.stdout)
    print(f"Dart Firebase integration gate: PASS ({count} tests, 0 skipped)")
    for path, names in REQUIRED.items():
        for name in names:
            print(f"PASS {path}: {name}")


def main():
    try:
        run_gate(Path(__file__).resolve().parent.parent, dict(os.environ))
        return 0
    except IntegrationGateError as error:
        print(f"Dart Firebase integration gate: FAIL ({error})", file=sys.stderr)
    except (OSError, subprocess.TimeoutExpired, UnicodeError):
        # CLI/debug output can contain environment/identity material. Fail with
        # a safe code; rerun the fixed Dart command locally for diagnostics.
        print("Dart Firebase integration gate: FAIL (runnerUnavailableOrTimedOut)",
              file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
