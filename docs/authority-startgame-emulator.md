# Atomic/idempotent StartGame — Firestore Emulator evidence

Local emulator-only evidence. No cloud workload and no production claim.

Canonical scope: Manifest v1.2, Domain/Persistence v0.7, Game Rules v1.1, Quality/Test Strategy v1.0, NFR-38, Risk R-31.

## What this test proves

- **TV-18 / lost-ACK duplicate StartGame:** one logical StartGame persists one room→game link, one public game, one private RNG state and one RoomCommand result. A retry of the same command returns the persisted gameId and starter allocation and cannot create a second public/private pair.
- The duplicate path remains safe even if a different test candidate gameId/seed/allocation is prepared before the retry: prior persisted command result wins.
- Frozen `rulesVersion` and a synthetic `resolvedPresetConfig` are copied consistently to room/public state.
- Private seed is stored only in `gameSecrets/{gameId}`; public state contains only a commitment.
- **TV-19 supporting concurrency:** two different StartGame commands racing on the same roomVersion converge on one accepted game pair; the loser becomes stale and leaves no orphan public/private game documents.

## Important boundaries

The fixture uses clearly synthetic preset/starter values and a test-only SHA-256 commitment. It does not implement or claim the canonical game RNG algorithm, DEC-065 content, starter-selection fairness, or actual Engine initialization.

This evidence does not yet prove:

- RNG output/counter retry safety or at-most-once consumption;
- actual RulesCatalog validation;
- real Engine initial state correctness;
- unauthorized StartGame security behavior beyond existing security-rule/auth suites;
- production Cloud Run/Firestore behavior;
- real deadline timeout transition or reconnect/takeover/debt behavior.

## Acceptance interpretation

Exact-ref Firebase Emulator + CI/review GREEN may promote the atomic/idempotent StartGame persistence sub-gate and TV-18. TV-19 may be promoted only to the extent defined by its canonical stale competing-lobby-mutation expectation. RNG/Engine integration remains the next gate rather than being inferred from this harness.
