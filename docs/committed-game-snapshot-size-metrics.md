# Committed public game snapshot size — ticket #106 / #19

## Scope and canonical inputs

[Ticket #106](https://trello.com/c/UXFkMCes) fills one remaining runtime size
boundary under [#19](https://trello.com/c/dk2nQOYj): accepted game transitions in
`FirstPlayableFirestoreRestStore.transactGame`. It adds no event, route, cloud
service, deployment, dependency, gameplay rule or schema/wire field.

Canonical sources read before implementation:

- [Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), page v173;
- [Domain v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1146948), page v7;
- [Persistence v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041), page v7;
- [Metrics & Observability Cost Validation](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1114390), page v1;
- [Security Addendum](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1146969), page v2;
- [ADR-010](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/754066), page v2.

These specifications require state-size and operation evidence. The exact
post-commit measurement point below is an implementation convention, not a new
canonical rule, TV/NFR identifier, budget limit or DEC-065 reconstruction.

## Measurement boundary

After `await transaction.finish(writes)` succeeds, the adapter measures:

```dart
utf8.encode(
  AuthorityPublicSnapshot(decision.publicStateAfter.toJson()).toCanonicalJson(),
).length
```

This expression is schematic for the non-null accepted state. The actual
helper handles null and protects the complete conversion, public validation,
canonical serialization and UTF-8 encoding. It reuses the existing public
wrapper; it does not introduce or relax persistence/public-wire validation.

The result is a **final-object gauge**, not an additive counter. A conflicted
commit never reaches measurement. On eventual success only the final accepted
`publicStateAfter` is measured, not intermediate decisions, prior reads or
their sum. The gauge travels through the existing result metrics and command
ingress event. Request-local capture still contains only the six additive
I/O/retry counters, including on later executor failure.

| Boundary | `snapshotBytes` meaning |
| --- | --- |
| Accepted `transactGame`, confirmed commit, valid public wrapper | Canonical UTF-8 bytes of that committed public game object. |
| No new public state: rejected, duplicate, collision, no-write decision | Unmeasured zero, even if a receipt was read or written. |
| Failed/exhausted commit | No successful result gauge; failure capture retains unmeasured zero. |
| Diagnostic conversion/validation/encoding failure after commit | Unmeasured zero; accepted result and I/O counters preserved. |
| Room entry, room/StartGame transactions, room/game reads | Existing unmeasured zero in the adapter. |
| Successful HTTP reconnect | Its separate validated-returned-snapshot measurement, unchanged. |

Internal system operations using the same accepted `transactGame` path receive
this result gauge too. This does not add a system caller, scheduler, diagnostic
event, presence protocol or deadline receipt migration.

The measure excludes receipts/results/events outside the state, membership
UIDs, private RNG, the Firestore document wrapper, indexes, HTTP envelopes,
headers/framing and delivery overhead. It is not `bytesRead`, `bytesWritten`,
billed storage, egress or proof that the client received an ACK. No snapshot,
hash, path or new field is published to the numeric/enum observability sink.

## Isolation and evidence

The protected helper runs after commit and catches diagnostic failures locally.
It cannot cause the retry loop to repeat a committed transition, replace its
accepted decision, or reset confirmed counters. Zero means unmeasured, not an
empty state or zero cost. Existing authoritative validation and original store
failure type/stack remain outside this diagnostic catch.

The 14 scripted REST regressions use the real adapter on numeric loopback with
explicitly synthetic decisions. RED before the production patch: 7 PASS and
7 failures reporting zero instead of the expected size. The identical test
file then passed 14/14 with zero skips. Coverage includes zero/one/two conflicts
with different attempt sizes, escaped/multibyte JSON, receipt/private payload
independence, interleaved operations, no-state decisions, terminal failures,
non-additive capture and the existing allowlisted ingress event.

One deliberately synthetic direct-adapter fixture is encodable by the existing
persistence projection but rejected by the stricter public wrapper. It proves
post-commit diagnostic failure isolation only: it is not a valid Engine/HTTP
trajectory, privacy permission or evidence of an observed production leak.

The existing real emulator tests add assertions without adding or replacing
their three gate cases. RED executed all three: one PASS, two size assertion
failures, zero skips. The store's recovered public state measured 1,706 bytes;
the vertical's two Rolls, Buy, Decline and Bid measured 4,629 / 4,689 / 4,439 /
4,997 / 5,028 bytes respectively, while each adapter gauge was zero. Existing
read/write, duplicate/rejected, StartGame/read and receipt-owner checks ran
unchanged before these assertions. The scripted peer alone is not Firestore
atomicity, actual cloud cost or production-distribution evidence.

After the production patch, the identical two emulator test files passed the
combined gate: 105/105 JavaScript and 3/3 Dart, zero failures or skips. Format
and focused analysis were clean; no test assertion was relaxed between RED and
GREEN.

With the pinned tools described in [the emulator README](../tool/firebase/README.md):

```sh
cd backend/command_service
dart test test/game_snapshot_metrics_test.dart
cd ../..
./tool/preflight.py --format
./tool/preflight.py
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

Foundation's opt-in emulator skips and macOS Linux-only goldens are not PASS.
Merge requires the eight remote checks on the exact final reviewed head,
including Android evidence; verify the accepted tree and post-main CI before
marking the scoped ticket Done.

## Remaining work

#19 stays open for other command/GET/pre-ingress boundaries, runtime aggregate
samples, client reconnect/takeover traces, NFR-48, cold/warm latency and genuine
limits/billing evidence. `coldStart=false` remains unmeasured. No sampling policy,
budget classifier, state-size enforcement or telemetry export is introduced.
#27 deadline/presence integration and ambiguous legacy system receipts remain
separate; this measurement does not decide their missing contracts.
