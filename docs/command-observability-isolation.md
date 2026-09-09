# Command diagnostic isolation — ticket #104

## Scope and sources

[Ticket #104](https://trello.com/c/q4UonVOl) restores the existing
non-authoritative observability contract in `CommandIngress.handle`. It is a
bounded defect correction under [ticket #19](https://trello.com/c/dk2nQOYj), not
a new gameplay, retry, timestamp or analytics policy.

Canonical context read before implementation:

- [Manifest v1.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), page v173;
- [Persistence v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041), page v7;
- [Metrics & Observability Cost Validation](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1114390), page v1.

The local `BestEffortAuthorityObservability` contract already states that
observability must not become an authoritative gameplay failure. The existing
[terminal accounting handoff](firestore-retry-metrics.md) preserves original
exceptions and request-local counters. No missing DEC-065 content is needed or
reconstructed for this fix.

## Reproduced defect

Before this correction, only the sink call and failure-event construction were
protected. The initial diagnostic clock was outside that protection, and the
successful event's clock and constructor ran inside the executor's error catch.
An exception while constructing an event therefore looked like an executor
failure even after the executor had returned successfully.

The reproduction uses the real HTTP ingress and an explicitly synthetic
executor with an observable effect. It demonstrates the response boundary, not
a real Firestore commit, a production incident or spontaneous clock failures.

| Injected diagnostic failure | Previous behavior |
| --- | --- |
| Initial diagnostic clock, with a valid supplied context | Executor never ran; HTTP 500. |
| Diagnostic clock after successful executor return | Executor ran once; HTTP 500 and a false `internalFailure` event. |
| Negative numeric result metric | Executor ran once; event validation threw, causing HTTP 500 and a false `internalFailure` event. |
| Sink throws after receiving the successful event | HTTP 200 was already preserved; this remains a control. |

These are failures in diagnostics, not permission to ignore an executor,
authentication, command validation or public-egress validation error.

## Protected diagnostic boundary

Command validation remains first. If no `IngressContext` was supplied, the
existing UTC authority timestamp must still be obtained before execution. A
failure obtaining that timestamp propagates and the executor does not run.
No timestamp is invented, replaced with a diagnostic time or silently defaulted.

After a valid context exists, diagnostic timing is best-effort. Failure to
capture a start time does not block execution; it omits that call's event rather
than inventing a latency. An end-clock or event-construction failure likewise
omits the event. Existing backward-clock clamping is retained.

The executor is awaited exactly once in its own failure boundary. On success,
the original value is returned and the existing `result.metrics` are used,
without adding captured counters a second time. On failure, the same exception
and stack propagate; the existing six captured additive counters feed the
failure event, with no inferred versions or snapshot/cold-start evidence.

Event construction and emission are protected diagnostics. They cannot enter
the executor's catch or produce a second event that reclassifies a successful
execution as failure. The numeric validator remains strict: invalid metrics
are not clamped into apparently valid evidence. Sink behavior stays best-effort.

This change does not move HTTP public-wire validation or response delivery
inside command telemetry. A command event still describes the executor result,
not a delivered ACK or successful client reconciliation. Authentication,
membership and client-contract errors keep their existing HTTP mapping. The
separate authority-clock capture at HTTP entry is unchanged.

## Verification

Against the original command implementation at `45766859`, the 48 new unit
cases had 26 behavioral failures and 22 passing controls; the 27 new HTTP cases
had 10 behavioral failures and 17 passing controls. With the correction, all
75 pass without skips. These counts describe the focused regression run, not
the independent emulator or remote-device gates below.

With the pinned Flutter 3.47.0 / Dart 3.13.0 toolchain:

```sh
cd backend/command_service
dart test test/command_ingress_diagnostic_isolation_test.dart \
  test/command_http_diagnostic_isolation_test.dart \
  test/authority_metrics_capture_test.dart \
  test/firestore_failure_http_mapping_test.dart
```

The new unit and numeric-loopback HTTP regressions distinguish authority time
from diagnostic time, assert once-only execution and unchanged outcomes, and
retain sink/executor-failure controls. The HTTP peer uses synthetic identity and
executor implementations; it is not an authentication-provider, Firestore
atomicity or durability test.

Keep the independent repository and real-emulator gates, from the root:

```sh
./tool/preflight.py --format
./tool/preflight.py
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

Use the pinned Node/Java/Flutter environment from
[the emulator README](../tool/firebase/README.md). A Foundation opt-in skip is
not executed emulator evidence, and a macOS golden skip is not Linux evidence.
Merge requires all eight jobs on the exact reviewed head, including Android
Tier-1, followed by verification of the accepted tree and post-merge CI.

## Limits

The command correction changes no executor, store, planner, recovery, GET,
transport contract, logging allowlist, service, deployment or billing policy. No raw
exception, command payload, identity or private state is added to logs.

The same PR includes a separate [Morgan development dependency security patch](morgan-log-safety.md)
to resolve its OSV failure. That narrow override does not change the Dart runtime
or the diagnostic boundary described here.

Completing this isolated defect does not close ticket #19, production
observability, cold/warm measurements, NFR-48, billing limits or M1 acceptance.
The existing emulator-first and `minInstances=0` baseline remains unchanged.
