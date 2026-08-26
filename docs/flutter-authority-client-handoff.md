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

The concrete Firebase/HTTP implementation belongs behind the two ports. It may
attach authentication out-of-band, but authenticated UID is never accepted in
the command body.

## Minimum Flutter repository behavior

1. Build one `AuthorityCommandRequest` from the canonical `RoomCommand` or
   `GameCommand`, with a durable `commandId` and current room/state version.
2. Store the request as uncertain before sending it.
3. Call `CommandGateway.send` without applying authoritative state
   optimistically.
4. On ACK, use the public result and replace cached state with the returned or
   streamed `AuthorityPublicSnapshot`.
5. On transport ambiguity, keep the same request. Reconnect with only
   `commandId + inputHashVersion + inputHash` and the observed state version.
6. `useDurableResult` resolves the prior command. `retrySameCommand` resends the
   byte-identical request. `failClosed` surfaces the safe error and never mints
   a replacement command ID.
7. Every reconnect snapshot replaces the cache completely. Client snapshot
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

The package tests prove canonical retry identity, semantic collision changes,
public/private rejection, monotonic reply versions, payload-free lost-ACK
reconciliation, and replacement snapshot behavior. Firebase Emulator evidence
for server persistence remains in the accepted #69/#71/#73/#74 chain.
