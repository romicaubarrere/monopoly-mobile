# Foundation boundaries

This repository keeps gameplay domain and wire contracts isolated from delivery infrastructure.

- `packages/game_core`: pure Dart domain implementation owned by Engine.
- `packages/game_contracts`: pure Dart domain/wire contracts shared across boundaries.
- `packages/backend_api`: transport-neutral authority-facing interfaces.
- `backend/command_service`: authority-side composition root; it invokes Engine/contracts and must not duplicate gameplay rules.
- `apps/mobile`: Flutter client; never authoritative for money, RNG, turns, properties, cards, deadlines, or command results.

Foundation intentionally contains no final board/economy/card fixture. DEC-065 content remains provenance-owned elsewhere; synthetic structural fixtures may be introduced later only when clearly marked.

The public development name is not embedded in package identifiers or domain boundaries so R-40 rebranding remains feasible before external distribution.
