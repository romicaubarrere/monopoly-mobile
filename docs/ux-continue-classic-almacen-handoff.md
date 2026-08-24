# M1 UX — Continuar Clásica Almacén executable handoff

## Scope

Layer U only. This slice materializes the missing Home → Continuar partida presentation path from UF-14 / US-024. Persistence, snapshot validation/migration, lobby/reconnect routing and authoritative restore remain caller-owned.

## Decision record

### Problema

The canonical IA and UF-14 require Home to expose a resumable Classic game, including a recovery path when snapshot preparation/migration fails. The executable Home only exposed Crear partida and Unirse con código, so the saved-game path had no mobile UI evidence.

### Alternativas

1. Make Home read persistence and decide whether a snapshot is valid.
2. Add a standalone resume screen disconnected from Home.
3. Keep Home presentation-only: accept a caller-owned saved-game presentation model and emit Continue/Retry intents.

### Decisión

Use option 3. `HomeScreen` accepts an optional `ClassicResumePresentation`; when present it renders `ClassicResumeCard`. The card has explicit `available`, `loading` and `recoveryError` visual states. Continue and retry are callbacks only.

### Rationale

This closes the UX gap without taking ownership of persistence, schema migration, authority, routing or reconnect policy. It also preserves the cross-surface contract: confirmed context stays visible while work is pending, and failure does not imply that stored evidence was overwritten.

### Impacto

- Home now exposes the canonical Continue Classic path when caller state says one exists.
- No saved game means no empty placeholder or false CTA.
- Loading blocks duplicate Continue intent while keeping the last confirmed summary visible.
- Recovery error keeps the saved-game summary visible and provides a retry affordance with factual copy.
- The Almacén visual language reuses `PaperPanel`, `StampBadge` and `TapeMark`; no screenshot-derived UI was introduced.
- 360dp / ~130% text and reduced-motion behavior are widget-testable.

## Authority and DEC-065 boundary

The UI does not persist, load, validate, migrate or mutate snapshots. It does not inspect `schemaVersion`, `stateVersion`, RNG state, cash, ownership, decks or any other private/canonical game payload. Exact game content remains caller-owned. Test copy is explicitly synthetic and does not reconstruct DEC-065.

## Verification target

- saved-game card absent when no caller-owned resumable state exists;
- available state emits one Continue callback;
- loading preserves confirmed summary and exposes no second Continue intent;
- recovery error states that the UI does not overwrite saved evidence and emits Retry only;
- 360dp + ~130% text has no critical overflow and CTA remains >= 44dp;
- formatter, analyzer, full widget suite and architecture gates green before merge.
