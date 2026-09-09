# Reconnect public snapshot size — ticket #19

## Scope and canonical inputs

This increment measures the validated public game snapshot returned by
`POST /v1/authority/reconnect` in its existing technical `recovery` event. It
does not add an event, change reconnect dispositions or instrument polling.

Canonical sources reviewed before implementation:

- [Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), page v173;
- [Persistence v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041), page v7;
- [Cost Model v0.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/950383), page v2;
- [Metrics & Observability Cost Validation](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1114390), page v1;
- [Product Analytics Event Contract](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1769575), page v1, subordinate to DEC-056.

Persistence requires state-size/reconnect metrics; the Cost Model requires
snapshot sizes and distinguishes them from document operations. These sources
do not prescribe this exact runtime extraction point. The boundary below is
an explicit implementation measurement convention, not a new canonical rule,
budget classifier or product-success definition.

## What is measured

For successful authenticated reconnect execution, `snapshotBytes` is:

```dart
utf8.encode(reply.snapshot.toCanonicalJson()).length
```

`reply.snapshot` is the existing immutable `AuthorityPublicSnapshot`. Its
existing canonical serializer emits compact, sorted-key, integer-only JSON.
Only the public game object is measured, after the entire reconnect reply has
passed the existing public-wire validation. No serializer, domain decoder,
gameplay validation or wire field is introduced by this increment.

This is a final-object size, not an additive operation counter. It is extracted
once from the successful result, separately from the six I/O/retry counters.
Repeated reads, retries, nested captures and a store's synthetic
`AuthorityExecutionMetrics.snapshotBytes` cannot add to or replace this value.
Concurrent requests use their own returned snapshot.

The measure excludes the reconnect envelope, disposition, uncertain-command
identity, receipt/result/events, Firestore document wrapper and indexes,
private state, HTTP headers/framing and delivery overhead. Changing only a
receipt cannot change the measured snapshot size. No hash, identifier, JSON
content or private payload is added to the sink: it still receives only the
existing allowlisted numeric/enum fields.

| Event boundary | Interpretation of `snapshotBytes` |
| --- | --- |
| Successful HTTP reconnect execution and public validation | Measured canonical UTF-8 bytes of that returned public game snapshot. |
| Failed reconnect execution/public validation | Existing zero fallback; no confirmed final size is asserted. |
| Generic recovery caller without a size extractor | Existing unmeasured zero fallback. |
| Accepted REST game transitions | Separate [committed game measurement](committed-game-snapshot-size-metrics.md), not supplied or summed by reconnect. |
| Accepted StartGame | Separate [initial public game measurement](start-game-snapshot-size-metrics.md); not a lobby size or reconnect counter. |
| Other commands and uninstrumented routes | This increment does not supply their sizes; zero remains unmeasured. |

Consumers must select the instrumented successful recovery boundary. Zero
fallbacks are not measurements of empty snapshots; the event stream is not a
complete sample of all persisted or delivered states. `coldStart=false` remains
unmeasured. There is no p50/max aggregation, sampling-policy change, state-size
limit or cost calculation here.

All six reconnect dispositions retain the existing technical
`outcome=success` / `reason=none` when execution and validation complete. That
does not mean an accepted command, delivered ACK, completed client
reconciliation or product `reconnect_result=success`.

## Diagnostic isolation

Size extraction runs inside the existing protected diagnostic block, not in
the authoritative executor, store transaction or public-validation operation.
It is never invoked for a failed execution. An extractor exception or negative
size omits the diagnostic event without replacing the successful return value,
its HTTP response, or any original exception. It cannot emit a second failure
event. Sink and diagnostic-clock failures retain their existing fail-open
behavior.

The capture continues to retain numeric I/O totals only. No snapshot, callback,
identity or payload is stored in the capture or observability sink. The existing
HTTP request temporarily retains its already-public result while formatting
the event and response; it does not persist another copy.

GET polling remains outside this scope: the current transport polls once per
second by default, and emitting an event per tick needs a separate volume and
classification review. Authentication/parsing failures still follow the
existing pre-ingress paths. No new telemetry SDK, cloud service, deployment,
BigQuery export or billing activation occurs; `minInstances=0` is unchanged.

## Verification and evidence limits

The existing runtime and scripted REST suites exercise the real HTTP ingress,
executor and public validation. Regression coverage must establish exact byte
sizes for all six dispositions, multibyte/escaped JSON, receipt independence,
counter/concurrency isolation, unchanged failed responses, and diagnostic
extractor/sink failures. Synthetic loopback peers are not Firestore atomicity
or cloud-cost evidence.

With the pinned Flutter 3.47.0 / Dart 3.13.0 SDK, from
`backend/command_service`:

```sh
dart test test/recovery_ingress_test.dart \
  test/reconnect_http_observability_test.dart \
  test/first_playable_authority_runtime_test.dart
```

The separate real Auth/Firestore vertical test compares recovery size with the
actual public snapshot returned by its emulator-backed runtime, while retaining
document-count, zero-write and private-field assertions. Its default Foundation
skip is not a PASS: execute the combined emulator gate with the pinned tools
described in [the emulator README](../tool/firebase/README.md).

```sh
./tool/preflight.py --format
./tool/preflight.py
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

All eight remote checks must pass on the exact reviewed head, including Android
Tier-1 and its evidence artifact. Verify the accepted tree and post-main CI.
The [reconnect accounting contract](reconnect-authority-metrics.md) and
[Firestore payload accounting](firestore-retry-metrics.md) remain separate
measurements. Ticket #19 stays open for remaining command/GET/pre-ingress boundaries,
client takeover traces, NFR-48, cold/warm latency, complete p50/max samples and
real limits/cost evidence. No missing DEC-065 content or new TV/NFR ID is invented.
