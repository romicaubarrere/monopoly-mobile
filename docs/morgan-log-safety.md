# Firebase development logger security patch

PR #97's first CI run rejected Morgan 1.11.0 in the development-only Firebase
lockfile: OSV job `102476814942`, run `34354852505`, head
`184b0f45d2bbfa90312e6243b5efb0ad89426515`. This is a dependency finding, not
evidence that a game command failed or that a production log was exploited.

## Provenance and bounded change

[GHSA-jxfw-x594-9x9m](https://github.com/expressjs/morgan/security/advisories/GHSA-jxfw-x594-9x9m)
identifies log injection through Unicode line separators in Morgan versions
before 1.12.0. The [upstream patch](https://github.com/expressjs/morgan/commit/fbf93833186920cc39bb19b247e4a86b61bef4fe)
extends escaping to C1 controls and U+2028/U+2029 and wraps registered string
tokens, retaining a single escaping pass for the Basic-auth username token.

The exact override is Morgan 1.12.0. The regenerated lockfile changes only its
version, registry URL and integrity. Firebase CLI remains 15.29.0 and Superstatic
remains 10.0.0; their existing Morgan ranges (`^1.10.0` and `^1.8.2`) accept this
patch. Other security overrides and the stream-json adapter remain unchanged.
No scanner exception is added, and no vulnerability threshold is relaxed.

The installed consumers use Morgan's `combined` string format. Firebase Hosting
supplies a normal byte-mode `Writable`; Superstatic enables the same format for
debug logging. Their package resolution and source call shapes are checked by
the regression, not assumed from Morgan's public API alone.

## Reproducible regression

With the pinned Node 24.19.0, from the repository root:

```bash
npm --prefix tool/firebase ci --ignore-scripts --no-audit --no-fund
node --test tool/firebase/test/morgan_log_safety.test.mjs
```

The seven installed-package tests cover shared dependency resolution, ordinary
combined output, NEL/U+2028/U+2029, existing C0/backslash escaping, registered
token calls without double escaping, and an HTTP request on numeric loopback.
The HTTP case verifies a real NEL header, one log record delivered as a Buffer,
one middleware continuation, and an unchanged 200 response/body. U+2028/U+2029
are exercised in memory, not as headers rejected by Node's HTTP parser.

Before the update, Morgan 1.11.0 produced one passing control and six failures:
five behavioral regressions and the expected fixed-version assertion. Synthetic
Basic-auth inputs are never printed by failing assertions. The same tests run
in the existing JavaScript suite; the complete Auth/Firestore + Dart gate is
documented in [the Firebase README](../tool/firebase/README.md).

On 1.12.0 all seven pass. The HTTP peer now declares `Content-Length: 2`
explicitly so the combined-format assertion does not depend on Node's implicit
header generation; no security assertion was weakened between RED and GREEN.
The updated local combined gate passed 105 JavaScript and three Dart tests,
without skips. That local result is not a substitute for final-head remote CI.

## Evidence limits

These checks do not start Firebase Hosting, deploy a service, exercise every
Hosting feature, or establish production log-pipeline behavior. Auth/Firestore
emulator success is separate integration evidence, not Hosting coverage.
Custom formatter functions that read raw request fields directly, or return
objects, are not covered by this token-escaping contract. No game runtime,
canonical gameplay rule, credential, billing control or cloud configuration is
changed. Final CI must pass for the updated PR head; the earlier failed run
remains part of the review history.
