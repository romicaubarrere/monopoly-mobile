# Reconnect receipt actor binding — ticket #105

## Scope and canonical contract

[Ticket #105](https://trello.com/c/PfUOzKC7) corrects receipt ownership in the
existing authenticated `POST /v1/authority/reconnect` flow. It introduces no
gameplay policy, endpoint, schema migration or deadline operation.

Canonical sources read before implementation:

- [Manifest v1.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), page v173;
- [Domain v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1146948), page v7;
- [Persistence v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041), page v7;
- [Security Addendum v0.3](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1146969), page v2.

Domain requires `actorUid` to be compared separately from semantic fingerprint.
An incompatible actor/hash is `commandIdCollision`, not a replay of the prior
result. Game membership still permits reading the current public snapshot; it
does not make a private command receipt belong to every member.

## Defect and correction

The executor previously replaced an incompatible actor's receipt hash with 64
zeros, preserving the receipt's result. Both wire and planner identity parsers
accept that hexadecimal shape. A different authenticated member who knew the
command ID could therefore request the zero hash and receive the other actor's
accepted/rejected result as `useDurableResult`, without knowing its real hash.

This was reproduced locally with synthetic gameplay and real Auth/Firestore
emulators. It is not evidence of a production incident, access across games,
private RNG disclosure or a gameplay mutation.

The executor now forwards the original receipt and its private `actorUid`
separately. The planner requires explicit nullable owner metadata: no receipt
means no owner; an existing receipt requires a nonempty owner. Invalid adapter
bindings fail closed without including identity in the error. Membership,
client-version and orphan-receipt validation retain their existing order.

The existing collision branch compares owner before ID/hash/version. It returns
`semanticCollision`, `failClosed`, and `commandIdCollision` without the previous
result. No fabricated fingerprint, inferred ownership or raw UID crosses the
public response boundary. The caller's uncertain identity remains unchanged.

The planner is the existing owner of reconciliation classification; keeping the
comparison there avoids duplicating collision/version validation in the
executor. Its internal named owner argument is required, so future callers must
make the binding explicit instead of inheriting an assumed-owner default.

Zero hashes are not prohibited by a new rule. A correctly owned matching
synthetic zero-hash receipt still resolves; a missing receipt still requests
retry of the same identity. The stored document format and all valid existing
receipts remain unchanged. Reads do not rewrite receipts or execute commands.

## Regression evidence

With the pinned Flutter 3.47.0 / Dart 3.13.0 toolchain:

```sh
cd backend/command_service
dart test test/reconnect_planner_test.dart \
  test/first_playable_response_adapter_test.dart \
  test/reconnect_http_observability_test.dart
```

The scripted HTTP suite uses real ingress, executor, planner and REST adapter
with synthetic identity and a numeric-loopback REST peer. Before the fix,
29 cases passed and two failed: other-owner accepted/rejected receipts with a
zero request hash. After the fix the identical test file passes all 31.
It also covers matching/other hashes, owner-zero, missing-zero and nonmember-zero
controls, exact public snapshot, read-only exchanges and safe metrics.

Planner/response-adapter tests pass 29 cases, including explicit owner/receipt
binding errors, accepted/rejected ownership, zero/nonzero hashes, client-ahead
and orphan-receipt validation. These are unit tests, not durable I/O evidence.

The existing real vertical test creates both an accepted command and a new
durably rejected stale command. Another authenticated member then requests each
receipt with the zero hash. Before the fix both were incorrectly resolved;
the final collected classification assertion failed. The combined gate reported
Dart failure; a separate sanitized run isolated that assertion, not setup.

After the fix the combined gate passes 105 JavaScript and three Dart tests,
without skips. The vertical test requires both collisions, legitimate owner
recovery, and unchanged public game, private RNG and receipt documents. Complete
canonical document fingerprints are compared only in memory with boolean
assertions; no private document or digest is printed. Its admin evidence reader
is restricted to the numeric-loopback `demo-board-game-local` emulator.

From the repository root, preserve all independent gates:

```sh
./tool/preflight.py --format
./tool/preflight.py
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

Use the pinned environment in [the emulator README](../tool/firebase/README.md).
Opt-in Foundation skips do not replace executed emulator tests. Merge requires
all eight checks on the exact reviewed head, including Android Tier-1, followed
by accepted-tree and post-merge CI verification.

## Boundaries preserved

Reconnect remains read/reconcile: current snapshot, three reads when requesting
a receipt, zero writes, no RNG advance and no changed deadline. Existing
[recovery diagnostics](reconnect-authority-metrics.md) remain technical execution
success even when reconciliation returns a collision; measured snapshot bytes
and the logging allowlist are unchanged.

No Firebase permissions, authentication provider, public wire field, hash
algorithm, dependency, billing setting or cloud deployment changes. System
deadline/legacy provenance work under #27 remains separate. No missing DEC-065
content, NFR-wide acceptance or production incident is inferred.
