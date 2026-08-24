# Canonical RNG executable handoff

This slice implements the frozen `hmac_sha256_counter_v1` contract without
changing gameplay, economy, card content, bot policy or client behavior.

## Decision

**Problem:** deterministic KAT parity alone does not prove that a transaction
retry or lost acknowledgement preserves exactly-once random effects.

**Alternatives:** keep a mutable RNG object; persist output and private counter
separately; or use an immutable pure-Dart successor plus one durable Firestore
transaction containing public result, private successor, command result and
state version.

**Decision:** use the immutable successor and atomic transaction boundary.

**Rationale:** callbacks starting from an identical private snapshot recompute
identical candidates. Only the accepted transaction persists the successor, and
the stable command ID returns the prior result after a lost acknowledgement.

**Impact:** TV-22..30 now have executable Dart and Emulator evidence. Private
seed, counters, raw HMAC values and future deck order remain outside mobile
source/state/assets/logs. Production seed generation, real Roll command wiring,
RulesCatalog/GameState and gameplay vertical slices remain separate work.
