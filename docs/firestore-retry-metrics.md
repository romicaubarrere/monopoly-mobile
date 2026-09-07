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
| `retryCount` / `conflictCount` | Existing bounded conflict-retry count, unchanged. |
| `schemaVersion` / `stateVersion` | Existing final authoritative result versions, unchanged. |

These are **logical adapter counts, not billed Firestore operations**. Payload
bytes exclude headers, TLS/HTTP framing, incomplete exchanges, listener fan-out,
storage/index overhead and provider billing rules. They are not snapshot sizes
or total network egress. The existing `snapshotBytes` and `coldStart` defaults
remain unmeasured; this increment does not turn them into runtime evidence.

A failed commit does not become a confirmed write because its request was sent.
Rollback failures remain best-effort; a complete error response contributes only
its byte lengths. Terminal failures still follow the existing safe-error path,
which does not return execution metrics: their all-zero ingress fallback is not
proof of zero I/O or zero cost. Full failure telemetry remains follow-up work.

Only integers are accumulated. No payload, path, UID, token, room code, private
RNG state or raw error is added to the observability allowlist. The existing
non-authoritative sink and its failure isolation are unchanged. No new analytics
SDK, BigQuery export, Monitoring metric, cloud workload or billing change occurs.

## Verification

With the pinned Flutter/Dart toolchain on PATH:

```sh
cd backend/command_service
dart test test/firestore_retry_metrics_test.dart
```

The 21 cases cover all three transaction families with zero/one/two conflicts,
no-write rollback, failed batch exchange bytes, room/game read-only recovery,
failed cleanup followed by success, interleaved operations on one store,
allowlisted ingress output and unchanged retry exhaustion. The peer counts
actual UTF-8 request and response payloads on numeric loopback, including a
multibyte error fixture. Expected byte totals are not inferred from character
counts or copied from the adapter's counters.

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

[Ticket #19](https://trello.com/c/dk2nQOYj) remains open for complete failure
telemetry, measured snapshot sizes and reconnect/takeover traces, production
cold/warm p50/p95, NFR-48 materialization and genuine budget/limit/cost evidence.
`minInstances=0` and emulator-first remain the baseline. This correction does
not close NFR-19/26/28/33/34 globally or reconstruct missing DEC-065 content.
