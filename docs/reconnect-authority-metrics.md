# Reconnect authority metrics — ticket #19

## Scope and canonical inputs

This follow-up to PR #93 observes the existing authenticated
`POST /v1/authority/reconnect` executor boundary. It does not change
reconciliation, membership, receipts, retry policy, wire contracts or gameplay.

Canonical sources checked before implementation:

- [Manifest v1.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), page v173;
- [Persistence v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041), page v7;
- [NFR v1.0](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819229), page v14;
- [Cost Model v0.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/950383), page v2;
- [Metrics & Observability Cost Validation](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1114390), page v1;
- [Product Analytics Event Contract](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1769575), page v1, subordinate to DEC-056.

These sources require observation of reconnect and operation counts, but do not
define a mapping from the six protocol dispositions to backend log outcomes.
No such mapping or new analytics taxonomy is introduced here. The existing
`AuthorityOperation.recovery` is used for **server execution diagnostics** only.

## Missing evidence reproduced

The existing runtime test executes a command, its lost-ACK duplicate and then
reconnect through the real HTTP/runtime/executor composition. Before this
increment it emitted only two command events. Requiring the third recovery
event failed against the previous implementation without changing the fixture
or the authoritative result.

The REST store already measures `readGame` and publishes its numeric snapshot
after cleanup. Reconnect bypassed any capture, so these measurements were lost.
The existing scripted and real-emulator evidence remain separate; an in-memory
fixture is not Firestore cost evidence.

## Measurement boundary

`AuthorityHttpIngress` authenticates and parses the request as before. It then
uses `CommandIngress.handleRecovery` around the executor and the existing
recursive public-wire validation. Only after that boundary completes does it
emit the recovery event. HTTP response writing remains outside the capture.

| Event field | Meaning for `operation=recovery` |
| --- | --- |
| `outcome=success`, `reason=none` | Executor returned and the public response passed validation. This includes all six unchanged dispositions, even `uncertainRejected`, `retrySameCommand` and `semanticCollision`. |
| `outcome=internalFailure`, `reason=internalError` | The observed server boundary threw. The original exception still determines the existing HTTP response; this generic diagnostic does not reclassify membership/domain failures or permit retries. |
| Six additive counters | The existing per-operation capture totals for completed adapter I/O, without summing returned metrics a second time. |
| `schemaVersion`, `stateVersion` | Versions from the validated successful public game snapshot only. Absent on failure. |
| `latencyMs` | Server time spent inside this execution/validation boundary, excluding authentication, request parsing and HTTP response delivery. Backward clock movement clamps to zero. |
| `snapshotBytes=0`, `coldStart=false` | Existing unmeasured defaults, not measurements or proof. |

Consumers must filter by `operation`: recovery `success` is **not** an accepted
game command, completed client reconciliation, delivered ACK, product
`reconnect_result=success`, or NFR-10 end-to-end success/latency. The actual
`ReconnectDisposition` and command resolution remain in the unchanged protocol,
not in a new log field. No state-gap or product event is synthesized.

The existing [Firestore accounting contract](firestore-retry-metrics.md)
continues to apply: logical document counts and completed payload bytes are
not billed operations, snapshot sizes or full network egress. In the real REST
adapter, reconnect reads two documents, or three when an uncertain command
identity requests a receipt; it performs no writes. Failed exchanges and
cleanup preserve only what the adapter actually measured.

## Why reuse the ingress orchestrator

Adding `handleRecovery` reuses the existing injected diagnostic sink and clock
without changing executor/store ports or requiring every runtime/fake to gain
another dependency. Refactoring command execution at the same time would
unnecessarily expand the behavioral surface, so `handle` is unchanged.

Adding `record(read.metrics)` in the executor was rejected: the REST store
already publishes from `finally`, so that would double count. A custom or
in-memory store that only returns metrics but does not publish capture snapshots
remains unmeasured here. Its zero fallback is not evidence of zero I/O.

Each call has a fresh single-use capture, including concurrent or nested calls
on the same ingress. Late work cannot alter emitted metrics or another request.
Only the existing numeric/enum allowlist reaches the sink: no UID, player ID,
room code, fingerprint, payload, private RNG state or raw exception is added.
Diagnostic clock, version extraction, event construction and sink errors cannot
alter the executor result/exception or cause a second error event. When those
diagnostics fail, the event is omitted rather than inventing measurements. This
does not remove the separate authority-clock requirement at HTTP request entry.

## Verification

With the pinned Flutter 3.47.0 / Dart 3.13.0 SDK on PATH:

```sh
cd backend/command_service
dart test test/recovery_ingress_test.dart \
  test/reconnect_http_observability_test.dart \
  test/first_playable_authority_runtime_test.dart
```

The orchestration tests use explicitly synthetic counters. The HTTP suite uses
a scripted loopback REST peer and the real store/executor/planner; it is not
Firestore atomicity or cloud-runtime evidence. The existing opt-in vertical
Auth/Firestore Emulator test now also asserts one successful recovery event
(three reads with a receipt), then a forbidden non-member recovery event (two
reads, no versions), positive payload bytes, zero writes and private-field
absence. The combined gate below must actually execute it; its default
Foundation skip is not evidence. Preserve the independent gates:

```sh
./tool/preflight.py --format
./tool/preflight.py
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

Run the latter commands from the repository root with the pinned environment
in [the emulator README](../tool/firebase/README.md). A skipped test is not a
PASS. Merge requires all eight remote jobs on the exact reviewed head, including
Android Tier-1.

## Remaining work

[Ticket #19](https://trello.com/c/dk2nQOYj) remains open. Public room/game GETs and
pre-ingress errors are not instrumented here. Polling volume/cost policy must
be considered before expanding events to GETs. Snapshot-size boundaries,
client reconnect/takeover traces, cold/warm p50/p95, NFR-48 materialization and
real budget/limit/cost evidence remain separate work.

There is no new service, Firebase Analytics SDK, BigQuery export, production
deployment or billing change. `minInstances=0` and emulator-first remain the
baseline. No new canonical NFR/TV/DEC IDs or missing DEC-065 content are invented.
