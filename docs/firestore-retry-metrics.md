# Firestore retry metrics — ticket #19

## Scope and evidence boundary

This increment fixes operation accounting in the existing Dart
`FirstPlayableFirestoreRestStore`. It does not introduce a telemetry service,
change gameplay or transaction retry policy, or establish production cost.

Canonical inputs, read before implementation:

- [M1 Specification Manifest & Evidence Registry](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), v173;
- Domain and Persistence v0.7, Quality and NFR v1.0;
- [Cost Model & Event Persistence v0.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/950383), v2;
- [RNG private-state cost addendum](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/753848), v1;
- [Security Addendum v0.3](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1146969), v2;
- [DEC-056 analytics baseline](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/786679), v1;
- [Metrics & Observability Cost Validation](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1114390), v1.

The previous adapter created counters for each transaction attempt and returned
only the final attempt's metrics. A game transaction whose commit conflicted
once reported three reads, although both attempts completed a three-document
batch. Failed HTTP exchanges also disappeared before their payload sizes could
be added. Eleven regression cases reproduce those omissions on the prior code.

## Accounting contract

The accumulator belongs to one invocation, not the shared store. Every retry
uses that invocation's accumulator; independent transactions and read-only
recovery calls cannot share it. The returned metrics are immutable values.

| Existing field | Meaning in this adapter |
| --- | --- |
| `firestoreReadCount` | Requested document paths in successful `batchGet` responses across all attempts, including missing documents and reads in an attempt whose later commit aborts. Failed batches do not add confirmed reads. |
| `firestoreWriteCount` | Document writes in successful commit responses only. Failed commits, read-only recovery and no-write decisions add zero. |
| `bytesRead` / `bytesWritten` | UTF-8 response/request payload lengths for completed HTTP exchanges across all attempts. Includes begin, batch, commit, rollback and error responses, counted before decoding or status classification. |
| `retryCount` / `conflictCount` | Returned successful results retain the existing bounded conflict-retry count. Terminal capture distinguishes additional attempts actually started from classified conflicts, as described below. |
| `schemaVersion` / `stateVersion` | Existing final authoritative result versions, unchanged. |

These are **logical adapter counts, not billed Firestore operations**. Payload
bytes exclude headers, TLS/HTTP framing, incomplete exchanges, listener fan-out,
storage/index overhead and provider billing rules. They are not snapshot sizes
or total network egress. The adapter's `snapshotBytes` and `coldStart` defaults
remain unmeasured. The separate [reconnect size follow-up](reconnect-snapshot-size-metrics.md)
measures the validated final public snapshot outside the store/capture; it does
not derive a size from these transport counters.

A failed commit does not become a confirmed write because its request was sent.
Rollback failures remain best-effort; a complete error response contributes only
its byte lengths. Terminal command failures now retain completed adapter I/O in
the existing ingress error event without wrapping or replacing the exception.
Uninstrumented/pre-I/O failures still use the existing zero fallback; that is
not universal proof of zero I/O or zero cost.

Only integers are accumulated. No payload, path, UID, token, room code, private
RNG state or raw error is added to the observability allowlist. The existing
non-authoritative sink and its failure isolation are unchanged. No new analytics
SDK, BigQuery export, Monitoring metric, cloud workload or billing change occurs.

## Terminal command accounting — follow-up to PR #92

`CommandIngress` creates a fresh `AuthorityExecutionMetricsCapture` around the
awaited executor call. Each logical store operation publishes one immutable
numeric snapshot from an outer `finally`, after final best-effort cleanup. This
also captures successful operations preceding a later executor failure. Multiple
awaited operations contribute once each; retries are not published separately.

The failure event sums only the six existing additive counters (retries,
conflicts, document reads/writes and payload bytes). Successful ingress still
uses `result.metrics` exactly as before, without summing it a second time. No
failed operation is assigned an inferred final schema/state version. The
existing `snapshotBytes=0` / `coldStart=false` remain unmeasured defaults.

The promoted Persistence/Cost specifications require retries, conflicts and
operation counts, but do not define a terminal-attempt formula. The following
is the adapter's explicit measurement convention, not a new gameplay rule or
retry policy: `retryCount` counts additional attempts actually started;
`conflictCount` counts errors classified by the existing HTTP-409/`ABORTED`
predicate, including the terminal conflict and begin/read-only failures, but
excluding rollback cleanup. Three conflicted attempts therefore produce two
retries and three conflicts. Begin remains outside the runner's retry/error
translation catch; observing its error does not cause another attempt.
Rollback errors remain excluded from the diagnostic conflict counter even when
the existing no-write closing path retries after a rollback conflict. That path
still increments `retryCount` for each additional attempt; the two counters are
not required to match. Its bounded retry and cleanup behavior are tested, not
changed by this increment.

### Why request-local asynchronous capture

The diagnostic channel uses a library-private `Zone` key instead of mutable
state on the shared store or reusable `IngressContext`. Passing a new port
through every store method/executor/fake would expand authoritative interfaces
solely for diagnostics; wrapping thrown errors would alter existing type-based
HTTP mapping. The selected scope leaves both interfaces and original error
identity/stack intact. `AuthorityExecutionMetrics` moved to a dedicated file and
is re-exported from its existing ingress import path for source compatibility.

Only `zoneValues` is supplied to Dart's [runZoned](https://api.dart.dev/dart-async/runZoned.html):
no error handler or new error zone is installed. A capture is single-use and
seals when its awaited execution ends. Nested captures shadow their parent;
late callbacks cannot mutate a sealed capture or fall through into its parent.
They are not claimed as completed-request I/O. No transaction, payload, error,
identity, callback or mutable accumulator is retained in the capture. Invalid
negative/overflowing snapshots are ignored, and failure-event construction and
sink failures cannot replace the original authority exception.

This instruments executor work inside ingress, not every HTTP request. The
[reconnect follow-up](reconnect-authority-metrics.md) now captures authenticated
POST reconnect execution and public validation as a separate recovery event.
Public room/game GETs still bypass capture and remain separate observability
work. No production telemetry, billing or NFR-wide closure is claimed.

## Verification

With the pinned Flutter/Dart toolchain on PATH:

```sh
cd backend/command_service
dart test test/firestore_retry_metrics_test.dart
```

The original 21 cases cover all three transaction families with zero/one/two conflicts,
no-write rollback, failed batch exchange bytes, room/game read-only recovery,
failed cleanup followed by success, interleaved operations on one store,
allowlisted ingress output and unchanged retry exhaustion. The peer counts
actual UTF-8 request and response payloads on numeric loopback, including a
multibyte error fixture. Expected byte totals are not inferred from character
counts or copied from the adapter's counters.

The terminal follow-up added 22 initially failing regressions: the old ingress
reported zero instead of completed document reads/payload bytes. They cover all
three transaction families, begin/batch/commit errors, exhausted retries,
malformed complete JSON/UTF-8, truncated responses, failed cleanup, evaluation
exceptions, successful work before failure, and scoped read-only failures.
Additional tests distinguish operation/cleanup conflicts and interleaved
successful/failed requests. Capture tests prove asynchronous/nested isolation,
sealing, unchanged error identity/stack, metadata exclusion, single-use and
fail-open sinks. Scripted HTTP mapping tests use a synthetic executor plus the
real ingress/store to preserve 403/400/500 errors; they are not full real-executor
or Firestore Emulator evidence.

```sh
cd backend/command_service
dart test test/firestore_retry_metrics_test.dart \
  test/authority_metrics_capture_test.dart \
  test/firestore_failure_http_mapping_test.dart
```

This scripted REST peer is **not Firestore atomicity/concurrency evidence**.
Keep the separate real Auth/Firestore Emulator suites and Android Tier-1 gate:

```sh
./tool/preflight.py --format
./tool/preflight.py
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

Use the documented pinned Node/Java/Flutter environment in
[the emulator README](../tool/firebase/README.md). No skipped test counts as a
PASS. Merge acceptance requires all eight remote jobs on the exact PR head.

## Remaining work

[Ticket #19](https://trello.com/c/dk2nQOYj) remains open for GET/pre-ingress
telemetry, measured snapshot sizes and reconnect/takeover traces, production
cold/warm p50/p95, NFR-48 materialization and genuine budget/limit/cost evidence.
`minInstances=0` and emulator-first remain the baseline. This correction does
not close NFR-19/26/28/33/34 globally or reconstruct missing DEC-065 content.
