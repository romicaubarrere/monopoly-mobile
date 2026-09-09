# StartGame public snapshot size — ticket #107 / #19

## Scope and canonical inputs

[Ticket #107](https://trello.com/c/iul4Hv47) extends the existing public-game
size measurement to the initial state created by accepted StartGame. It does
not measure lobby objects or combine several documents into a snapshot gauge.

Sources reviewed before implementation:

- [Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), page v173;
- [Persistence v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041), page v7;
- [Cost Model v0.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/950383), page v2;
- [Metrics & Observability Cost Validation](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1114390), page v1;
- the existing `ReadyStartPlan`, room transaction decision and their persistence projection.

Persistence distinguishes room truth, confirmed public game and private RNG;
StartGame creates the game/public-private pair with the room change and receipt
atomically. Cost Model associates the authoritative snapshot with the game and
requests size evidence. Neither document specifies a mixed room/game gauge.

This implementation selects **only `ReadyStartPlan.publicState`** as a new,
explicit and reversible measurement convention. It does not claim that the
canon prescribes this extraction point. Measuring lobby states in the same field
would need a separate discrimination contract; that is outside this increment.

## Contract and version interpretation

After `transactRoom` confirms `finish(writes)`, it passes
`decision.startPlan?.publicState` to the existing protected helper from
[the game transition measurement](committed-game-snapshot-size-metrics.md).
The helper validates the public wrapper and measures canonical UTF-8 JSON.

| Existing field | Meaning for an accepted StartGame event |
| --- | --- |
| `operation` | Still `roomCommand`; no new event or operation kind. |
| `stateVersion` | Still `decision.reply.versionAfter`, the resulting **room version**. It is not the version of the measured game object. |
| `schemaVersion` | Existing room operation schema metadata, unchanged. |
| `snapshotBytes` | Final initial public **game** object only, whose own state version is zero. |
| Six I/O/retry counters | Existing logical adapter accounting, unchanged and separate from the gauge. |

Do not join the measured object's version to `stateVersion` as if they were the
same domain. The room event does not gain a game-version field, command type,
gameId, private identifier or other observability attribute. No event schema or
authority response is changed to support this diagnostic value.

Only a confirmed accepted StartGame has a non-null `startPlan`. SetReady,
CreateRoom/JoinRoom, reads, duplicates, collisions and rejected decisions retain
unmeasured zero. A duplicate returns its existing receipt; measuring a current
room or game read would incorrectly assign a new size to that replay.

The gauge excludes the room patch, safe result summary, receipt, membership
UIDs, private RNG/decks and Firestore/HTTP envelopes. It is not their sum, a
transport byte count, total storage or proof of ACK delivery. Changing private
or receipt payload length does not change the public-object measure.

## Retry and diagnostic isolation

Measurement occurs after the final successful commit. Aborted attempts do not
contribute a size; capture still accumulates only the six existing counters.
Terminal store failures preserve their original classification/stack and the
unmeasured failure-capture gauge. Conversion, public validation or encoding
failure inside the diagnostic helper returns zero without replacing an accepted
result, dropping counters or retrying a committed operation.

The runtime still establishes candidate StartGame material outside its
transaction retry callback. A new HTTP replay currently calls that factory
before receipt deduplication; this increment does not move or instrument it.
Tests must not claim that a factory is invoked just once across separate HTTP
requests. The relevant replay properties are the same durable game/result,
zero new writes and unchanged confirmed public/private state.

No new service, endpoint, SDK, dependency, scheduler, gameplay transition,
authorization rule, persistence schema, wire field or cloud deployment occurs.
`coldStart=false` remains unmeasured; the observability allowlist is unchanged.

## Verification and evidence boundary

The focused numeric-loopback REST tests use the actual adapter and explicitly
synthetic decisions. They distinguish zero/one/two conflicts, final candidate
size, UTF-8/escaping, private/receipt independence, room/game version metadata,
non-StartGame paths, terminal failure, capture and post-commit fail-open behavior.
Synthetic candidates of different sizes are a diagnostic boundary test, not
permission to regenerate canonical starters or RNG during a real retry.

The two existing real emulator files retain their three gate cases. They
compare StartGame size with the public game actually recovered/observed and
retain four accepted writes, room-version metadata and game version zero.
Exact request replay preserves the durable gameId/public state/private RNG and
adds no writes or new measured gauge. Prior game-command/reconnect-size and
receipt-actor-binding regressions stay in the same flow.

RED before the production patch: the 14 peer cases reported eight PASS and six
size failures; the identical file then passed 14/14 without skips. The combined
emulator RED passed 105 JavaScript tests and failed its Dart gate. A sanitized
diagnostic run confirmed three Dart executions, one PASS and two failures only
at the new size comparisons: store 4,163 bytes and the two HTTP StartGame states
4,215 / 4,263 bytes, all previously reported as zero. Existing replay, metadata
and #105/#106 checks completed successfully before those final comparisons.
The unchanged emulator tests then passed 105/105 JavaScript and 3/3 Dart, zero
failures or skips. No assertion was weakened between RED and GREEN.

A synthetic public-wrapper-invalid decision, if used to exercise the protected
helper, is not a valid Engine/HTTP trajectory or permission to persist private
data. Loopback peers are not Firestore atomicity, production sampling or billing
evidence. Zero defaults are unmeasured, not empty snapshots.

With the pinned tools from [the emulator README](../tool/firebase/README.md):

```sh
cd backend/command_service
dart test test/start_game_snapshot_metrics_test.dart
cd ../..
./tool/preflight.py --format
./tool/preflight.py
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

No skipped test counts as PASS. Review the complete diff; all eight checks,
including Android evidence, must pass on the exact final PR head. Verify the
accepted tree and post-main CI before moving this scoped ticket to Done.

#19 remains open for unmeasured routes, aggregate samples, client/takeover traces,
NFR-48, cold/warm latency and genuine cost/limit evidence. No missing DEC-065 or
ambiguous legacy deadline receipt contract is inferred here.
