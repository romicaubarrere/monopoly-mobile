# Firebase emulator baseline

M1 uses a local-only Firebase project ID: `demo-board-game-local`.

This baseline starts Auth and Firestore emulators. It never deploys, requires no production Firebase project, and contains no production credentials.

Security intent follows the canonical Threat Model + M1 Security Addendum v0.3 and Persistence v0.7:

- rooms and confirmed public games are member-readable and client-write-denied;
- room-code locators are client inaccessible;
- room/game operation records are client inaccessible;
- `gameSecrets` is client inaccessible;
- unknown collections are deny-by-default;
- anonymous identity continuity can be exercised locally through Auth emulator.

The fixtures are synthetic Foundation fixtures, not DEC-065 game content.

Run from repository root after installing dependencies in this directory:

```bash
cd tool/firebase
npm ci --ignore-scripts --no-audit --no-fund
npm run emulators:test
```

This original command retains the JavaScript-only suite. The required CI job
now uses the combined JavaScript + Dart gate:

```bash
# Node 24.19.0, Java 21, Python 3 and pinned Flutter 3.47.0/Dart 3.13 on PATH.
# Resolve workspace dependencies at the repository root first:
flutter pub get --enforce-lockfile
npm --prefix tool/firebase ci --ignore-scripts --no-audit --no-fund
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

Run that block from the repository root with emulator ports available. The CLI
starts a fresh local demo instance, runs JavaScript then Dart (not concurrently),
propagates failure, and shuts down its emulators. No existing data is cleared or
exported by this entrypoint. Dependencies stay lockfile-pinned; generated
`tool/firebase/node_modules/` is ignored, not vendored.

`DEBUG` is removed only for that local invocation: Firebase CLI debug output can
dump the subprocess environment. Do not upload its raw debug logs. The Dart gate
prints only fixed test identities and safe status codes, not raw test payloads.

See [gate behavior, regression evidence and limitations](../../docs/dart-firebase-integration-gate.md).
