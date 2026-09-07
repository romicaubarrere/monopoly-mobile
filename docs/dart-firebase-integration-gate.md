# Dart Firebase integration gate — ticket #13

## Gap and scope

The required Firebase job previously executed only JavaScript. Foundation ran
the Dart suite without emulator environment variables, so the two opt-in Dart
integration cases were skipped even on green commits. Android Tier-1 is a
separate live device path, not execution evidence for these named Dart tests.

Both existing Dart files were run locally before changing the gate: three tests
passed (one safety test plus two integration cases), with zero skips, on accepted
PR #90 head `f587bd34ee1ebaf793d02d8ce2cba34f4a35544c`. The problem was missing CI
execution/enforcement, not missing test implementation.

Canonical basis: [Manifest v1.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338),
version 173, and [Quality & Test Strategy v1.0](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/917505),
version 14. Exact-ref evidence and emulated Auth/Authority/persistence integration
are required; a skip is not acceptance. Product/QA ticket #67 released the VP0
horizontal lock on 4 September 2026. No canonical decision/registry is changed.

## Implemented gate

The existing `firebase-emulators` job keeps its read-only permissions and pinned
Node/Java/Actions/dependencies. It additionally sets up the same pinned Flutter
SDK and resolves the Dart workspace with `--enforce-lockfile`.

`npm run emulators:test:all` starts the local Auth/Firestore emulators for
`demo-board-game-local`, then runs:

1. The complete unchanged JavaScript `npm test` suite.
2. `tool/firebase_dart_integration.py`, which invokes both existing Dart files
   with fixed paths, the JSON reporter and `--concurrency=1`.

The three required file/name identities are in the runner's `REQUIRED` mapping.
Renaming a required test must update that mapping in the same reviewed change;
deleting, hiding or filtering it cannot silently pass.

Why inspect JSON: `dart test` exits successfully and reports `done.success=true`
even when tests were skipped. The gate therefore requires each named test's
successful, nonhidden, nonskipped `testDone`, complete discovery/completion, a
successful final report and exit 0. Any error event, including one arriving
after successful completion, fails. Hidden suite-loading tests are not proof.
The parser uses the JSON protocol supplied with pinned `package:test` 1.31.1.

Before starting Dart, the runner requires the exact demo project and both
numeric-loopback emulator endpoints with valid ports. Missing environment fails
before tests, rather than producing green skips. It cannot select cloud targets,
test filters, production credentials or deployment actions.

The original `npm run emulators:test` remains JavaScript-only for compatibility.
Foundation intentionally retains its no-emulator test path; the required Firebase
job now owns positive execution of the integration cases. No green Foundation-only
run should be described as passing those integration cases.

## Reproduction and diagnostics

See [Firebase setup and combined command](../tool/firebase/README.md). Use a fresh
local emulator invocation; these existing fixtures use fixed demo document IDs.
The runner neither clears data nor imports/exports emulator state. JavaScript and
Dart run sequentially, so their fixtures do not race across languages.

Offline guard regressions run in `./tool/ci.sh` and can be run separately:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tool/test -p 'firebase_dart_integration_test.py'
```

They cover skips despite success, missing/renamed/hidden/wrong-file tests,
incomplete/unsupported/malformed reports, failed or late-error cases, duplicate
identities, interleaved protocol events, unsafe/missing environment, subprocess
failure/timeout and required-job wiring without emulator or cloud access.

The integration runner prints fixed test identities and safe error codes only.
It does not publish raw test errors, token-bearing payloads, stderr or environment
values. For a failure, rerun the fixed command under your local demo emulators
and inspect its diagnostics privately:

```sh
# Working directory: backend/command_service; emulator environment must be set.
dart test --concurrency=1 test/first_playable_firestore_rest_store_emulator_test.dart test/first_playable_http_firestore_vertical_emulator_test.dart
```

Do not upload raw Firebase CLI debug logs: they can include the environment.
No new raw-log artifact upload is added by this gate.

## Acceptance boundary

This adds execution evidence for the real Dart REST store and Auth → HTTP →
Authority → Firestore wire path, including existing room/start/game/reconnect
and lost-ACK assertions. It does not add new gameplay or controller transitions,
prove takeover/reclaim concurrency, replace Android Tier-1, or close iOS,
production latency/cost, human playtest, VP1 or release-readiness criteria.

Ticket #13 remains open for those broader exits. Merge acceptance for this
increment still requires all eight exact-final-head jobs green, including Android.
