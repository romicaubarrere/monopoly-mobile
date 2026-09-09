# Durable game-command replay before catalog lookup — #110

## Canon and bounded defect

[Ticket #110](https://trello.com/c/eKtrw90R) restores the existing human-command
idempotency order. The
[Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), v173,
and [Persistence](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041),
v7, remain canonical: classify a prior command by actor, command ID and semantic
fingerprint before evaluating a new gameplay transition. This follows the
[room replay correction](durable-room-replay-dependencies.md) without changing
its preparation or Create/Join behavior.

Previously, `executeCommand` resolved the game catalog before the existing
receipt classification in `_evaluateGameCommand`. A valid stored view with an
accepted or rejected receipt could therefore return `authorityUnavailable` if
the catalog was unavailable or incompatible, instead of resolving the durable
result. This is a reproduced dependency-failure scenario, not evidence of an
incident or invalid deployed catalog.

## Historical result is not current-state certification

The human game transaction callback first invokes one extracted receipt helper.
It preserves all four comparisons: verified actor UID, commandId,
inputHashVersion and inputHash. An exact match uses the existing response
adapter, retaining the historical public result, original rejection if any,
and historical versions. An incompatible identity returns the existing
`commandIdCollision` response at the current state's version, without disclosing
the original result. Neither response includes a current public snapshot.

Only receipt absence continues to catalog resolution and the existing
membership, controller, version and Engine checks. No catalog error is caught
or converted to a receipt miss. Errors and stack traces retain their original
identity; no fallback catalog or new rules are introduced.

This order does not certify that the current board or frozen preset agrees with
the server catalog. New commands, GET and reconnect still resolve and validate
the current catalog, even when a prior receipt exists. Resolving an uncertain
command and obtaining a valid replacement snapshot remain separate operations.

The REST store still reads and decodes public game, private gameSecrets and the
requested receipt before invoking the callback. Public/private envelopes,
membership agreement, RNG material and receipt identity must still be valid.
Missing/corrupt documents and malformed durable results continue to fail closed;
this is not a receipt-only read path or a corruption-recovery bypass. Ingress
still verifies authentication and recomputes the command fingerprint first.

Internal bankruptcy-deadline and tax/free-parking operations retain their own
existing classification order. No legacy/system receipt interpretation,
namespace, schema, codec, wire contract, store API, Engine, RNG, retry policy,
SDK, dependency, permission, cloud service or deployment is changed.

## Measurement and regression layers

Duplicate/collision still measures three document reads, zero writes and
`snapshotBytes=0`, ending the transaction with rollback. Captured request and
response bytes are real REST transfer bytes; the capture does not inherit a
public snapshot gauge or reply metadata. Healthy Roll still confirms its three
writes once and measures the committed public-state size separately.

`game_replay_catalog_store_test.dart` uses the actual executor, Engine, pinned
catalog repository, codec and REST store with a numeric-loopback scripted peer.
Receipts come from real accepted Roll or rejected stale-version executions.
The peer supplies alternate catalogs for missing rules, board mismatch and
frozen-preset mismatch. It checks replay identity and absence of snapshot,
actor/hash collision privacy, full persisted-document equality, original error
and stack, and the same current view's new-command/GET/reconnect failure guards.
Missing public/private documents and an invalid receipt still fail before the
catalog callback. Zero/one/two simulated conflicts retain identical attempted
writes and one confirmed RNG advance. Its top-level field-mask implementation
is test-only; this peer does not prove Firestore isolation, production latency
or billed traffic.

The real HTTP/Firestore gate retains all earlier actor-binding and game/StartGame
size assertions. After accepted and rejected game receipts exist, it captures
the complete healthy replay reply, then makes the catalog unavailable for the
exact same owner, other-actor and changed-hash requests. The six responses must
match their healthy baselines, with three reads, zero writes/gauge and unchanged
public, private RNG and receipt fingerprints. Guest snapshots remain unchanged.
Private documents are compared in memory only; neither they nor credentials
are logged by the diagnostic.

The frozen REST file went from 8 PASS / 8 expected failures to 16/16 PASS,
without skips or assertion changes. Its SHA-256 is
`6b94d034a66eac0b116b2e86f55e75e72a2a2604d1b6c1a9ae5781e7bb38b5b2`.
The HTTP file is frozen at
`20ee93d362bad9b8a52b1b8e14d628b6fec72e3bd49875b2fc5e0750bc62c1a6`.
The RED JavaScript stage passed 105 tests. A sanitized Dart diagnostic then
reported 1 PASS / 2 FAIL / 0 skips: the HTTP test reached its final assertion
with all six new replay cases returning `authorityUnavailable`; the separate
store integration test timed out. That timeout is not counted as proof of the
replay defect and the complete unchanged gate must pass before acceptance.

GREEN then passed the complete 105 JavaScript + 3 Dart emulator gate, zero
skips, with those same frozen files. An earlier GREEN attempt had failed an
unchanged JavaScript case with an offline emulator error; local tooling and
secret-hook subprocesses also timed out during heavy host load. Serial reruns
retained every original gate and timeout. Full preflight/`ci.sh` passed with
206 formatted files unchanged, 530 backend tests and 226 Flutter tests; existing
informational diagnostics and platform/opt-in skips are not reclassified as PASS.

Run the new REST suite, full `./tool/preflight.py` (which runs `./tool/ci.sh`),
and `env -u DEBUG npm --prefix tool/firebase run emulators:test:all` using the
pinned SDKs. Skips are not PASS. All eight exact-head remote jobs including
Android PASS/artifact, accepted-tree verification and post-main CI remain
required before Done. #14/#19/#27 and absent DEC-065 content remain outside
this ticket's closure.
