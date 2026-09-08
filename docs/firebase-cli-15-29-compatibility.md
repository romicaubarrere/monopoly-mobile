# Firebase CLI 15.29 compatibility and CSV security remediation

## Scope and authority

[Ticket #103](https://trello.com/c/f6Plas5J) repairs the existing
[Dependabot PR #85](https://github.com/romicaubarrere/monopoly-mobile/pull/85).
It is separate from completed maintenance ticket #86 and introduces no
replacement PR. [Dependency Baseline v0.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1048642)
(page v2), under the Manifest, requires a ticket, changelog, compatibility review
and exact-head CI. Neither a proposed version nor an old green run is acceptance.

Changes stay under Firebase development tooling: CLI 15.28.1 → 15.29.0, the
existing stream-json adapter and an exact csv-parse 7.0.2 security override.
Flutter/Dart, Node 24.19.0, Temurin 21, Firebase JS 12.18.0, rules-unit-testing
5.0.2 and the other security overrides remain fixed. No runtime/gameplay,
Firestore rules, schema, credentials, deployment or billing changes occur.

## Why the existing proposal failed

The previous compatibility guard admitted only Firebase 15.28.1 with
stream-json 3.5.0. PR #85 changed the package and lock but not that guard.
Its Firebase and Android jobs failed before starting the emulators with
`Unsupported Firebase stream-json compatibility target`. Running the original
script against the installed 15.29.0 lock reproduced the same failure locally.

The [15.28.2](https://github.com/firebase/firebase-tools/releases/tag/v15.28.2)
and [15.29.0](https://github.com/firebase/firebase-tools/releases/tag/v15.29.0)
release notes were reviewed, including the debug-path addition and Functions
emulator IPC error fix. This harness uses Auth/Firestore emulators, not Functions
or deployment. Keep `DEBUG` unset and do not upload raw Firebase debug logs.

The official npm tarballs, integrity-checked against their published metadata,
contain byte-identical compiled versions of the three adapted modules:
`lib/commands/auth-import.js` (5,520 bytes), `lib/database/import.js`
(8,349 bytes) and `lib/frameworks/next/index.js` (26,569 bytes). The installed,
adapted copies also compare byte-for-byte between these CLI versions.
Firebase still declares stream-json ^1.7.3 and stream-chain ^2.2.4.

Retargeting to exactly **15.29.0 / 3.5.0** therefore retains all 13 existing
rewrites. No version range or fallback is introduced. stream-json 3.5's ESM
exports use lowercase paths and explicit Node-stream factories; the adapter
preserves the existing `.asStream()` / `.withParserAsStream()` usage.

Every expected old target must occur exactly once with no new target, or an
already adapted target exactly once with no old target. Missing, duplicated or
mixed sites fail. All three modules are read/prevalidated before the first
write; a repeat invocation is byte-idempotent and writes nothing. This prevents
partial adaptation on upstream-content drift, not an atomic filesystem update:
if a write itself fails, reinstall the lock with `npm ci` before retrying.

## csv-parse: a separate security blocker

PR #95's dependency scan subsequently identified the already installed
csv-parse 5.6.0 as vulnerable to
[GHSA-8cw4-87c7-c6xx](https://github.com/adaltas/node-csv/security/advisories/GHSA-8cw4-87c7-c6xx).
The maintained advisory affects versions below 7.0.2; duplicated `__proto__`
columns with both column options enabled can replace a parsed record's prototype.
The regression test reproduces the changed prototype with 5.6.0 and requires
an intact prototype plus an own data property with 7.0.2.

Both Firebase CLI versions still request csv-parse ^5.0.4. No fixed 5.x release
was published when checked; merely upgrading the CLI would leave OSV red.
The precise **7.0.2 override** upgrades this transitive dev dependency without
adding an OSV exception, patching a still-vulnerable version number or changing
the scanner. Existing unrelated overrides/exceptions are not broadened.

Compatibility review covered the [published changelog](https://github.com/adaltas/node-csv/blob/master/packages/csv-parse/CHANGELOG.md)
and the [CommonJS distribution](https://csv.js.org/parse/distributions/nodejs_cjs/).
7.0.2 retains `dist/cjs/index.cjs` and the named `parse` export, with no additional
runtime dependency. The only csv-parse consumer in the Firebase tarballs is
[auth-import](https://github.com/firebase/firebase-tools/blob/v15.29.0/src/commands/auth-import.ts):
`parse()` without options and `readable` / `read()` / `end` returning arrays.
It does not use the vulnerable options. That bounds exposure; it is not an
excuse to suppress the advisory or claim all CLI features have been exercised.

## Executable checks and limits

The new adapter harness tests use synthetic module text and injected filesystem
operations: exact versions, all three targets, idempotence, ambiguous/missing
patterns and no writes before complete prevalidation. They are not real-package
execution by themselves. Installed-package tests additionally load all three
adapted Firebase modules and execute their stream shapes:

- Auth users selection, empty users, fragmented UTF-8 and truncated JSON;
- RTDB root/path filtering preserving the outer subtree structure;
- Next dependency-name/tree extraction with its unchanged parser flags. Those
  flags intentionally omit scalar versions; the test does not change them to
  obtain a different output.

CSV tests resolve the corrected CommonJS package from both Firebase's consumer
and the harness, tie its API to the installed source, exercise arrays, quoting,
CRLF, empty fields/input, byte-fragmented Unicode and malformed input, and
assert the advisory's prototype boundary. These are offline parser tests, not
execution of `auth:import`, an Auth upload or a production workload.

From the repository root, with the pinned environment described in
[the emulator README](../tool/firebase/README.md):

```sh
npm --prefix tool/firebase ci --ignore-scripts --no-audit --no-fund
npm --prefix tool/firebase run prepare:stream-json-v3-compat
node --test tool/firebase/test/prepare_stream_json_v3_compat.test.mjs \
  tool/firebase/test/stream_json_v3_compat.test.mjs \
  tool/firebase/test/csv_parse_compat.test.mjs
./tool/preflight.py --format
./tool/preflight.py
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

Keep the real Firebase integration gate (including all three Dart cases without
skips), Android Tier-1 artifact and all eight exact-final-head remote checks.
After protected merge, verify the accepted tree and post-main CI before marking
this scoped ticket Done. Snapshot PR #95 needs fresh-base acceptance afterward;
its unrelated false-positive handling is not included here.
