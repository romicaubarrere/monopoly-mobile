# Flutter ↔ Authority client handoff — VP0

This is the minimum transport-neutral boundary required to bind the accepted
Ready/Start → Roll/movement → Buy/Decline/Auction → reconnect First Playable.
It does not define UI, Firebase configuration, or gameplay rules.

## Packages and ownership

- `board_game_contracts` owns canonical pre-game `RoomCommand` envelopes.
- `board_game_core` owns canonical `GameCommand`, command types, and public game
  state. Depending on these pure-Dart contracts does not run gameplay logic in
  Flutter.
- `board_backend_api` owns the Flutter-facing Authority ports and public wire
  wrappers: `CommandGateway`, `AuthoritySnapshotRepository`, command request,
  command reply, snapshot, and reconnect identity/result.
- `board_command_service` remains server-side. Flutter must never import its
  planners.
- Engine remains the only owner of command legality, dice, movement, cash,
  ownership, auctions, deadlines, and state transitions.

`HttpAuthorityWireTransport` is the concrete mobile HTTP adapter behind the two
ports. It attaches a Firebase ID token only as a Bearer header, requires HTTPS
outside loopback Emulator origins, and exposes only the three VP0 routes below.
Authenticated UID is never accepted in a command body.

## HTTP surface

- `POST /v1/authority/commands` sends the canonical command envelope and its
  recomputable semantic fingerprint.
- `POST /v1/authority/reconnect` sends the observed version and, when needed,
  only the uncertain command identity.
- `GET /v1/authority/games/{gameId}` reads replacement public snapshots.

`AuthorityHttpIngress` verifies the Firebase identity, decodes the same
`board_backend_api` wire contracts, captures `requestReceivedAt` once, and
passes the verified identity separately to `AuthorityHttpExecutor`. The
executor remains responsible for membership and for composing the accepted
Engine planners with durable Firestore transactions; no game rule exists in
the HTTP layer.

## Authority → Firestore decision contract

`FirstPlayablePersistenceCodec` is the single versioned projection between the
Dart executor and the Firestore transaction adapter. Every decision carries
`schemaVersion=1`, its `room` or `game` family, the typed public reply and only
the patches/receipt allowed for that disposition. The adapter rejects a family
or schema mismatch before any write.

StartGame carries `memberUidByPlayerId` only inside the private `gameSecrets`
document and derives the public `memberUids` membership index from the same
atomic decision. The adapter fails closed if either side is missing or the two
sets disagree. The public game document and Flutter snapshot never contain the
direct mapping, seed, RNG counters or future deck order.

Create/Join uses the same separation before a game exists. The Firestore
adapter transacts the hashed `roomCodes/{codeHash}` locator, public
`rooms/{roomId}`, private `roomSecrets/{roomId}` membership and durable room
command receipt together. Plaintext room codes are rejected from every
persistent document. Accepted public and private membership sets must agree;
duplicate/collision decisions perform zero writes.

`FirstPlayableAuthorityMaterialFactory` derives room/player/game identifiers,
the six-character room code, SHA-256 locator hash and Start seed with an
infrastructure-private HMAC key that is separate from game RNG state. It must
reproduce identity material for the same `commandId` across instances. Create
expiry is authority time plus the configured TTL; Firestore transaction retries
reuse the single material instance produced at ingress.
The live composition must use
`FirstPlayableAuthorityRuntime.withEnvironmentMaterials`; it reads
`FIRST_PLAYABLE_AUTHORITY_HMAC_KEY_BASE64` only from the server process
environment, requires canonical base64 decoding to at least 32 bytes, and never
accepts the key from Flutter, an HTTP request, Firestore, logs, or repository
configuration. Room-code TTL remains an explicit infrastructure value rather
than client input.
The executor returns the Create code transiently, persists only its hash, and
reconstructs the same code for an exact lost-ACK retry. Join accepts a locator
only while `expiresAt > requestReceivedAt`, requires an open room, validates the
next seat against the canonical preset/catalog, and updates public/private
membership once. A changed fingerprint, actor or material hash is a collision
with zero writes.

## Minimum Flutter repository behavior

1. Start without a client-minted `playerId`. Create/Join must return the
   authority-assigned `actorPlayerId` in their accepted public result; the
   confirmed context rejects a missing or changed identity before any gameplay
   command can be constructed.
2. Build one `AuthorityCommandRequest` from the canonical `RoomCommand` or
   `GameCommand`, with a durable `commandId` and current room/state version.
3. Store the request as uncertain before sending it.
4. Call `CommandGateway.send` without applying authoritative state
   optimistically.
5. On ACK, use the public result and replace cached state with the returned or
   streamed `AuthorityPublicSnapshot`.
6. On transport ambiguity, keep the same request. Reconnect with only
   `commandId + inputHashVersion + inputHash` and the observed state version.
7. `useDurableResult` resolves the prior command. `retrySameCommand` resends the
   byte-identical request. `failClosed` surfaces the safe error and never mints
   a replacement command ID.
8. Every reconnect snapshot replaces the cache completely. Client snapshot
   upload or merge is intentionally absent from the API.

## Public/private boundary

The public snapshot may include `rngVersion` and `rngCommitment`. It rejects
tokens, UID fields, seeds, counters, private deck state, and future deck order at
any depth. The concrete adapter must preserve the same rule and must never read
`gameSecrets` into Flutter.

## Capability mapping

- Ready/Start: send canonical `RoomCommand` requests and switch to the returned
  `gameId`/public snapshot.
- Roll/movement: send `RollDice` with `expectedStateVersion`; render only after
  the Authority result/snapshot advances once.
- Buy/Decline/Auction: send the Engine command type/payload from the current
  pending decision; never calculate cash, bidder rotation, or winner locally.
- Reconnect/fault: observe public snapshots; resolve an uncertain request using
  the durable identity contract; preserve the authority-owned deadline.

## Verified server composition status

The Firebase Emulator Suite proves the Auth bootstrap, Firestore rules and the
transaction adapter independently. It does not yet prove the complete HTTP
path. `FirstPlayableAuthorityRuntime` is a Dart composition root and requires a
Dart `FirstPlayableAuthorityStore`; the only concrete Firestore adapter in this
branch is currently the JavaScript
`FirstPlayableAuthorityFirestoreStore`. That module cannot be injected into the
Dart port and no process boundary between them is defined.

The minimum server-side binding still required is therefore:

1. a Dart-compatible implementation of `FirstPlayableAuthorityStore` (or an
   explicitly specified same-runtime boundary) that preserves the existing
   versioned decision codec and atomic Firestore transactions;
2. a server-owned `RulesCatalog` resolver keyed by the frozen rules version and
   preset persisted for the room/game; Flutter must never supply that catalog;
3. a concrete Firebase ID-token signature verifier for the Dart ingress, with
   Emulator acceptance enabled only for the configured loopback Emulator host.

None of these gaps changes the Flutter repository contract. Mobile continues
to send canonical commands and consume replacement public snapshots only.

The package tests prove canonical retry identity, semantic collision changes,
public/private rejection, monotonic reply versions, payload-free lost-ACK
reconciliation, replacement snapshot behavior, authoritative Create/Join
membership, and an authenticated loopback HTTP round trip from
`WireAuthorityClient` through the typed ingress. The complete Auth + Firestore
Emulator Suite passes 57/57 tests on this branch, including the concrete
transaction adapter, rules, idempotency/lost-ACK, reconnect and public/private
guards. The remaining vertical gap is binding the Dart HTTP runtime to that
durable store and real token verification, then executing the flow from Flutter
and collecting Tier-1 device evidence.
