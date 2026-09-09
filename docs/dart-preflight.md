# Canonical Dart preflight

Trello [#89](https://trello.com/c/bbhnGTAp) implements the reversible process
decision in [M1 Quality Process Review — Recurrent Dart formatter churn](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/5472257).
The Manifest and its promoted specifications remain canonical. This changes
delivery tooling only: no gameplay, product, DEC/ADR/NFR/R/TV, dependency upgrade
or runtime change.

## One supported local entrypoint

Use Python 3.9+ and the already installed Flutter **3.47.0** / Dart **3.13.0** on
`PATH`. Flutter's pin is read from `.fvmrc`; the exact bundled Dart expectation
is checked in `tool/preflight.py`. Both the Flutter-reported Dart and the `dart`
executable must match, so an older standalone Dart earlier on PATH fails closed.
An SDK change must update these expectations through normal review, not bypass
the check. No SDK is downloaded or installed by the preflight itself.

From the repository root:

```bash
./tool/preflight.py
```

If using FVM, the equivalent is `fvm exec ./tool/preflight.py` with the pinned SDK
already available. No hook, global configuration change or credential is needed.

The full preflight runs Foundation via `tool/ci.sh`, then the existing repository
policy and artifact scans. Foundation checks the SDK, resolves dependencies with
`--enforce-lockfile`, checks formatting, and retains the registry, tooling tests,
analyzers, Dart/Flutter tests, observability/security smokes and architecture
checks. Any failure stops the command with a nonzero exit code; a later gate
cannot hide an earlier failure.

The existing [GitHub Actions SHA guard](github-actions-sha-policy.md) checks
direct action references, including steps with `name:` before `uses:`. Its
documented lexical scope is separate from the actionlint workflow-syntax gate.

Source formatting is read-only by default:

```bash
dart format --output=none --set-exit-if-changed apps packages backend
```

Dependency resolution and test execution may update normal SDK caches and
generated build/test files; “read-only” here means no automatic rewriting of
tracked Dart source or self-push. The SDK needs its normal cache/configuration
permissions. Do not solve an SDK permission failure by changing source or
weakening a gate.

## Explicit local formatting

To request source edits and then the full preflight:

```bash
./tool/preflight.py --format
```

The SDK is validated before dependency resolution or source edits. Formatting
targets only `apps`, `packages` and `backend`, the same scope as the original
gates. It does not reset, commit, stage, push or discard existing changes.
Inspect the diff afterward, especially in a dirty working tree.

`--format` is rejected when either `CI` or `GITHUB_ACTIONS` indicates CI, even
when the other variable is false. This is a guard against accidental invocation,
not a security boundary against callers deliberately clearing their environment.

For focused format diagnosis, `./tool/preflight.py --format-only` runs only the
pinned dependency/format stage. Locally, `--format --format-only` explicitly
formats just that scope. Neither focused mode is evidence that the full
preflight passed.

## Shared CI stage and submission checklist

Foundation and PR Code Review both call
`python3 -B tool/preflight.py --format-only`. The default full entrypoint delegates
to Foundation; Foundation invokes only the focused stage, so there is no
recursive gate invocation. PR Review retains its existing analyzer/reviewdog,
secret, dependency and actionlint jobs and permissions. No temporary formatter
probe, write token, self-formatting workflow or self-push is introduced.

Before a push or PR:

1. Run `./tool/preflight.py` using the pinned SDK.
2. If formatting fails, run `./tool/preflight.py --format` explicitly.
3. Inspect `git diff` and run the default preflight again; source formatting must
   produce zero changes. Commit only the intended files.
4. Recheck the exact final commit. Any later source drift must still fail CI.
5. Push/open a PR only with the project's required authorization. Merge still
   requires exact-final-head CI + PR Review green and explicit authorization.

Local success does not replace Firebase emulator, Android Tier-1, Linux golden,
dependency or remote security acceptance. A later normal PR that reaches
formatter-green on its first remote run is a supporting process signal, not
statistical proof or a reason to weaken remote gates.

## Executable evidence

`tool/test/preflight_test.py` covers pinned and mismatched SDKs, mixed PATH,
prerelease rejection, invalid pins, locked dependency failure, CI write refusal,
formatter failures, shared CI wiring and propagation of every full gate's exit
code. A temporary dependency-free fixture exercises the actual CLI with the real
pinned formatter across all three source roots:

- unformatted source fails without changing its bytes;
- explicit local format produces expected canonical Dart bytes;
- a second read-only run passes without changes;
- deliberate subsequent drift fails CI without rewriting it.

The fixture has isolated temporary Flutter configuration, contains no product
data and needs no Atlassian credential. The real formatter test is explicitly
skipped only when Flutter/Dart are absent in a standalone Python test run; normal
Foundation CI requires and validates the SDK before running the suite, so it
executes this test. Unit tests use fake subprocesses; they do not claim to replace
the real formatter evidence.
