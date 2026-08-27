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
  wrappers: `CommandGateway`, `AuthoritySnapshotRepository`,
  `AuthorityRoomSnapshotRepository`, command request, command reply, room/game
  snapshots, and reconnect identity/result.
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
- `GET /v1/authority/rooms/{roomId}` reads replacement public lobby snapshots.
- `GET /v1/authority/games/{gameId}` reads replacement public game snapshots.

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

Create also freezes the server-selected `rulesVersion` in the public room.
`PinnedFirstPlayableRulesCatalogRepository` owns the active immutable catalog
for new rooms and resolves only that exact persisted version for Join,
Ready/Start and gameplay. It verifies the persisted board identity and complete
`ResolvedPresetConfig` before invoking Engine. Unknown versions, unknown
presets, duplicate registry entries or mutated frozen config fail closed.
Flutter supplies only `presetId`; it never supplies catalog JSON or version
selection.

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

`FirstPlayableAuthorityClient.httpWithDeviceStorage` is the minimum mobile
composition root. Flutter injects the Firebase ID-token provider, Authority
origin, one durable string key-value port, durable command-id source,
client-instance id and `presetId`. `FirstPlayableAuthorityDeviceStorage` owns
the versioned keys and both canonical codecs. The backend API package owns
transport, wire decoding, session, confirmed context, command resolver, binding
and public snapshot subscription. Flutter does not assemble those ports,
serialize Authority contracts or synchronize state versions itself.

1. Start without a client-minted `playerId`. Create/Join must return the
   authority-assigned `actorPlayerId` in their accepted public result; the
   confirmed context rejects a missing or changed identity before any gameplay
   command can be constructed.
2. Build one `AuthorityCommandRequest` from the canonical `RoomCommand` or
   `GameCommand`, with a durable `commandId` and current room/state version.
3. Store the request as uncertain before sending it.
4. Call `CommandGateway.send` without applying authoritative state
   optimistically.
5. `SessionFirstPlayableAuthorityBinding` reads one authenticated
   `AuthorityPublicRoomSnapshot` immediately before Start, so a Ready change
   from another actor advances the confirmed `roomVersion` without screen code
   or client inference. Failure blocks before any command is sent. The room
   snapshot contains only player IDs, kinds and readiness; Flutter never maps
   or receives Firebase UIDs.
6. On ACK, use the public result and replace cached game state with the returned
   or streamed `AuthorityPublicSnapshot`.
7. On transport ambiguity, keep the same request. Reconnect with only
   `commandId + inputHashVersion + inputHash` and the observed state version.
8. `useDurableResult` resolves the prior command. `retrySameCommand` resends the
   byte-identical request. `failClosed` surfaces the safe error and never mints
   a replacement command ID.
9. Every reconnect snapshot replaces the cache completely. Client snapshot
   upload or merge is intentionally absent from the API.
10. If the pending-command repository cannot read or durably write, block
    before transport with `pendingCommandStoreUnavailable`. Canonically corrupt
    data preserves `pendingCommandCorrupt`; reconnect does not contact Authority
    until the durable identity can be restored safely.


`JsonPendingAuthorityCommandStore` is the minimum lost-ACK persistence adapter.
Flutter supplies one atomic device key-value read/write pair; the backend API
package owns canonical serialization, strict restoration, the 64 KiB bound and
command-aware clear. Corrupt, non-canonical or mismatched persisted data fails
closed, so process restart cannot silently replace the uncertain command. The
session converts repository read/write failures into a blocked safe state before
network mutation; it does not leak storage exceptions into Flutter presentation.

`JsonFirstPlayableSessionLocatorStore` persists only canonical `roomId` and the
optional `gameId`. It never stores actor identity, UID, versions, snapshots or
rules. After process death, `FirstPlayableAuthorityClient.restore` uses those
locators only to perform authenticated public room/game reads; Authority
re-establishes actor membership and confirmed versions before another command.
The key-value write callback must remove the named key when its value is null.
If locator decoding or either authenticated replacement read fails, the client
retains that safe error and blocks command transport until restore succeeds.

## Public/private boundary

The public game snapshot may include `rngVersion` and `rngCommitment`. The
public room snapshot exposes Authority player IDs and readiness, never UID
membership. Both reject tokens, UID fields, seeds, counters, private deck state,
and future deck order at any depth. The concrete adapter must preserve the same
rule and must never read `roomSecrets` or `gameSecrets` into Flutter.

## Capability mapping

- Ready/Start: the binding refreshes lobby context from the authenticated room
  snapshot before Start, sends the canonical `RoomCommand` with that confirmed
  version, then switches to the returned `gameId`/public game snapshot.
- Roll/movement: send `RollDice` with `expectedStateVersion`; render only after
  the Authority result/snapshot advances once.
- Buy/Decline/Auction: send the Engine command type/payload from the current
  pending decision; never calculate cash, bidder rotation, or winner locally.
- Reconnect/fault: observe public snapshots; resolve an uncertain request using
  the durable identity contract; preserve the authority-owned deadline.

## Verified server composition status

`FirstPlayableFirestoreRestStore` is the executable same-runtime Dart binding
for `FirstPlayableAuthorityStore`. It uses Firestore's canonical REST
`beginTransaction` → `batchGet` → `commit` flow, retries only transaction
conflicts, and calls the existing typed Authority evaluator after consistent
reads. It applies only the versioned `FirstPlayablePersistenceCodec` decision;
duplicate/collision decisions roll back with zero document writes. Public room
and game documents are decoded independently from `roomSecrets`/`gameSecrets`,
then their membership sets and envelope versions must agree before Engine or a
snapshot can be reached.

Production construction requires a short-lived OAuth access-token provider and
uses only `https://firestore.googleapis.com`. Emulator construction accepts
only a numeric loopback `FIRESTORE_EMULATOR_HOST`; its owner credential cannot
be sent to a remote host. The real Firestore Emulator test executes Create,
exact lost-ACK replay, Join, Ready, Start, public/private game reconstruction,
game mutation and receipt recovery through this Dart adapter.

This closes the Dart↔Firestore repository gap, but does not claim the complete
Flutter HTTP path or Tier-1 device proof. Bootstrap still needs a promoted
canonical server catalog bundle. The current `RulesCatalog & PresetConfig
Specification v0.1` defines shape and invariants but explicitly does not freeze
the final board, economy or card values, so this branch does not invent
production catalog content.

Production Firebase ID-token verification is now concrete:
`GoogleFirebaseIdTokenSignatureVerifier.live()` validates RS256 signatures with
Google's secure-token certificates. Its bounded HTTPS fetcher uses the canonical
certificate endpoint, honors `Cache-Control: max-age`, coalesces concurrent
refreshes and fails an unknown `kid` from a fresh cache without another fetch.
Envelope and claim checks remain in `FirebaseIdentityVerifier`, so audience,
issuer, expiry, issue time, auth time and subject use the same injected clock and
fail-closed error boundary. Token, signature and certificate material is never
returned in errors or observability fields.

Auth Emulator identity is also concrete but remains a separate fail-closed
boundary. `FirebaseAuthEmulatorIdentityVerifier.fromEnvironment()` accepts only
the Emulator's unsigned `alg: none` token with an empty signature, normal
Firebase claims, a `demo-*` project and an explicit loopback
numeric `FIREBASE_AUTH_EMULATOR_HOST`. It rejects resource-backed project IDs,
remote, hostname or scheme-bearing hosts, signed/keyed tokens and invalid claims. The real Auth
Emulator smoke obtains an anonymous ID token and verifies that its subject is
the returned local member without logging either value. Production continues
to use the RS256 verifier and cannot accept this token shape.

None of these gaps changes the Flutter repository contract. Mobile continues
to send canonical commands and consume replacement public snapshots only.

The package tests prove canonical retry identity, semantic collision changes,
public/private rejection, monotonic reply versions, payload-free lost-ACK
reconciliation, replacement snapshot behavior, authoritative Create/Join
membership, and an authenticated loopback HTTP round trip from
`WireAuthorityClient` through the typed ingress. The established Auth +
Firestore Emulator Suite covers the JavaScript adapter, rules,
idempotency/lost-ACK, reconnect and public/private guards. The additional
Dart-store Emulator integration proves the server runtime can bind directly to
the same durable contract. The remaining vertical gap is registering a
promoted canonical catalog bundle, then executing the complete HTTP flow from
Flutter and collecting Tier-1 device evidence.
