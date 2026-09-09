# Rejected CreateRoom replay preserves its public result — #112

## Canon and reproduced defect

[Ticket #112](https://trello.com/c/lqHvbLrx) restores room-command idempotency,
not a new room-code policy. The
[Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), v173,
promotes [Persistence v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041)
and [Domain v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1146948).
The same command ID, actor and semantic hash return the prior typed result;
incompatible identity returns collision with zero mutation.

The live executor reconstructs a Create code from stable authority material:
accepted Create returns that code transiently, while its receipt persists only
the hash. Previously the reconstruction also ran for rejected Create receipts,
although the original rejection never contained a code. An exact retry therefore
added `publicResult.roomCode` while preserving the error and rejection status.

A diagnostic with the actual factory/executor/codec and a JSON-round-tripped
receipt in a shared in-memory store reproduced `invalidPresetDraft`: the first
reply omitted the code and replay added it. An accepted control retained the
same transient code and result. Neither replay wrote a new receipt or mutation.
Those counters are modeled, not Firestore measurements or production evidence.

## Correction boundary

Reconstruct the transient code only for Create whose durable outcome was
accepted. `FirstPlayableResponseAdapter.duplicate` first validates the persisted
result and returns the existing transport status `duplicate`.
`AuthorityCommandReply.isRejectedOutcome` distinguishes the original rejected
outcome; checking transport status for `accepted` would incorrectly remove the
code from every successful lost-ACK retry.

Rejected replay retains the durable public result, error and versions exactly,
without adding a code or inventing a new rejection. Accepted replay still
reconstructs its original code without persisting plaintext. The five existing
actor/commandId/hash-version/hash/material-code-hash comparisons remain intact.
Join and Ready/Start/game replay behavior is unchanged.

No HMAC/generation/key policy, expiry/reclaim, capacity, catalog, authentication,
wire/schema/codec/store API, RNG/Engine, UI, SDK, dependencies, timeouts, cloud
service or new canonical rule is introduced. In particular this does not change
the existing `roomCodeUnavailable` rejection or introduce an internal candidate
retry policy. A room code is a locator, not a credential; the reproduced extra
field is not by itself proof of unauthorized room access.

## Regression layers

The numeric-loopback REST peer exercises actual factory, executor, codec and
store paths. Rejections must originate from an initial execution, not a fabricated
receipt. For the occupied-code case, first create a real accepted room and then
explicitly inject that code/hash into another candidate while retaining its own
room/player IDs. This is a synthetic collision fixture, not a discovered HMAC
collision. Initial Create reads four documents even if the candidate room is
missing; accepted Create confirms four writes, rejection one, replay/collision
zero. Peer byte totals and document comparisons do not prove Firestore isolation
or billed cost.

The real Auth/HTTP/Firestore vertical retains both complete gameplay chains and
all #105–111 controls before running the new scenarios. A real material factory
serves only the new test commands. The occupied-code branch explicitly injects
the same synthetic collision described above; other material fixtures are intact.

The new HTTP cases check accepted lost-ACK, `invalidPresetDraft`,
`roomCodeUnavailable` and rejected-receipt actor/hash collisions. They compare
public results through booleans and fingerprint complete locator, public room,
private room and receipt documents in memory, preserving missing documents too.
The occupied accepted room is separately checked unchanged. Evidence reads are
restricted to the numeric-loopback demo emulator, and plaintext codes must be
absent from persisted documents. No token, UID, code or private payload is printed.

The initial real HTTP RED completed in 5.7 seconds. Review then identified that
a malformed private evidence response could escape through `FormatException`
with a fragment of its body. The helper now translates decoding and fingerprint
failures into fixed safe codes, as the existing evidence helper already does.
No replay assertion was changed. The final frozen HTTP RED file has SHA-256
`0210765a5e53b8dc795f678035b99681f2c8f0e02618e6f595fd85ff22053736`.
Its repeated three Dart emulator tests completed in 5.5 seconds: two PASS,
one FAIL, zero skips. Its final assertion observed `sameResult=false` and
`codeAbsent=false` in both rejection cases after the accepted control and gameplay checks
passed. There was no transport error or timeout. This Dart-only RED does not
claim a new JavaScript RED run.

The 12-case REST peer RED passed ten cases and failed only the two rejected
replays, which incorrectly contained a code. Their measured I/O, error/version
and document-preservation assertions passed before the code-absence assertion
failed. Accepted replay, six identity controls and three corrupt-receipt guards
passed. The frozen peer SHA-256 is
`57257bd9b56c32a885243fb143d82ca6a762308c2acaffe8b3f766c345c65c53`.

After the production correction, the unchanged REST file passed all 12 cases,
zero skips, and the canonical complete emulator gate passed all 105 JavaScript
and three Dart tests, zero skips. Both frozen hashes remained unchanged. The
review fix to the evidence reader happened before the final RED, not between
that RED and GREEN.

Final-commit preflight/ci.sh, secrets and emulators must be recorded separately.
Acceptance requires all eight exact-head remote jobs including Android
PASS/artifact, a protected merge with the reviewed tree and all four post-main
jobs before Done. Skips never count as PASS.
