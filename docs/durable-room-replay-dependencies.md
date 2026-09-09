# Durable room replay before new-attempt dependencies — #109

## Canon and bounded defect

[Ticket #109](https://trello.com/c/URVTR4nA) restores the existing room-command
idempotency order in the live executor. The
[Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), v173,
and [Persistence](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041),
v7, remain canonical: the same command ID, actor and semantic hash return the
prior result; incompatible identity returns collision without mutation.
Atomic StartGame retains its gameId and allocation after a lost ACK.

Previously, `_executeRoomCommand` awaited new StartGame material and resolved
the room catalog before classifying the loaded receipt. Missing/failed material
or an unavailable catalog could therefore replace an already committed result
with `authorityUnavailable`. This was reproduced with injected dependency
failures; it is not evidence of a production incident or a broken catalog today.

## Execution and failure order

StartGame still awaits its material factory once per HTTP request, outside the
transaction retry callback. The executor retains either the candidate or the
original preparation error and stack, both scoped to that request. It does not
cache material/errors between requests or regenerate material during retries.

Inside each existing room transaction callback:

1. A single extracted helper checks the persisted actor, commandId,
   inputHashVersion and inputHash, exactly as before.
2. An exact receipt returns its durable result; an originally rejected result
   remains a duplicate carrying the original rejection/error. An incompatible
   receipt returns collision with no original game/allocation result.
3. Without a receipt, a preparation failure is rethrown with its original stack.
4. Otherwise catalog, room identity/membership/version and transition checks
   retain their existing order.

SetReady uses the same receipt helper and its replay no longer needs a catalog.
New SetReady commands still validate the catalog. CreateRoom/JoinRoom, game
commands, public reads and legacy system operations are outside this change.
No authentication comparison, public contract, store API, codec, schema,
Engine rule, retry count or observability field is added or relaxed.

Only preparation is caught. Store/read/decode errors, malformed receipt results
and catalog errors are not swallowed by that catch. If the store cannot supply
a valid view, the executor cannot assert that a durable duplicate exists: the
store failure takes precedence over the deferred preparation failure. This is
not a recovery bypass for corrupt/missing room documents.

The factory remains awaited, even on replay. This fix does **not** solve a
never-completing Future, introduce a timeout/cancellation policy or promise one
factory invocation across separate HTTP requests. It changes which completed
preparation outcome is required, not preparation latency.

## I/O and measurement boundary

The existing REST store still loads public room, private room mapping and room
receipt in its three-document batch. Duplicate/collision performs no writes,
ends with rollback and retains `snapshotBytes=0`. Duplicate versions come from
the durable result; collisions retain the current room version as before.
No current game snapshot is substituted for a receipt.

A failed preparation with no receipt now performs three document reads and
rollback instead of failing before any store I/O. Capture retains those measured
reads and request/response bytes before the original error propagates. This
bounded cost is necessary to discover whether a durable result already exists;
it is not an unmeasured zero-I/O failure or a new retry policy.

Healthy StartGame still confirms four writes once. Zero/one/two conflict fixtures
retain one material, identical attempted write payloads and existing counters.
The [initial public-game size gauge](start-game-snapshot-size-metrics.md) remains
postcommit, non-additive and separate from failure capture.

## Executable evidence

The new executor suite uses real planners and receipts produced by an initial
execution, with a synthetic in-memory store. It covers accepted/rejected replay,
missing/synchronous/asynchronous preparation errors, catalog absence, actor/hash
and misbound-commandId collisions, SetReady, malformed receipt, error/stack
identity, awaited preparation/retries and isolation of concurrent requests.
Its modeled I/O is not measured Firestore traffic.

The new numeric-loopback REST peer uses the actual executor, codec and store.
It checks complete persisted-document equality, measured transfer bytes, three
reads/zero writes on replay, original failure capture and zero/one/two conflicts.
The peer is not Firestore atomicity, production latency or billing evidence.

RED/GREEN with unchanged files: executor 3 PASS/18 FAIL became 21/21 PASS;
REST peer 3 PASS/9 FAIL became 12/12 PASS, with no skips. SHA-256 respectively:
`48593e1e9257244ffab7da697a5e1a04156cedb8d57333f0b69c1c761291a02a` and
`941daf38054ead00cee367c8bad7a1d100286accd280d0789e4cdc9a37e1a938`.

The existing HTTP/Firestore gate additionally injects material/catalog/both
failures only after two genuine StartGame commits and reuses the exact pending
request. It retains earlier actor-binding, game-size and StartGame-size checks.
Public game, private RNG and receipt are compared in memory via fingerprints;
guest room/public snapshots must stay unchanged. No private payload is logged.
The RED ran 105 JavaScript tests successfully, then three Dart cases with two
PASS and one failure, zero skips. The sole assertion failure was the final map
of six replay cases returning `authorityUnavailable` instead of duplicates.
The identical HTTP file then passed with the full 105 JavaScript / 3 Dart gate,
zero skips. Its SHA-256 stayed
`0f3c23bc9c78c29efb670b06f96eca45ce81be375a14d0a09e4c6be26a60fbfb`.

Run the two `room_replay_dependency*_test.dart` suites, full preflight and
`env -u DEBUG npm --prefix tool/firebase run emulators:test:all` with the pinned
SDKs. Skips are not PASS. All eight exact-head remote jobs, including Android
evidence, accepted-tree verification and post-main CI remain required for Done.

#14/#19/#27 remain open for their other evidence. No cloud workload, deployment,
new service, legacy receipt reinterpretation or missing DEC-065 content is
introduced by this correction.
