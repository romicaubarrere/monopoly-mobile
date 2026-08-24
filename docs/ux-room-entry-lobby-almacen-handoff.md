# M1 UX — Room Entry + Lobby Almacén handoff

Status: implementation candidate for executable Layer U evidence.

Canonical inputs: M1 Specification Manifest & Evidence Registry v1.2; M1 UX/UI & Design System Specification v0.1; Visual Direction — Almacén uruguayo intervenido + Character System v0.2; existing accepted Room Entry/Lobby executable behavior from PR #6.

## Problema

Create Room, Join Room and Lobby already had accepted mobile behavior, accessibility basics and caller-owned state, but their presentation remained on the pre-Almacén generic Material baseline. That created a visible identity discontinuity after Home and the main game surfaces migrated to the approved A+C direction.

## Alternativas

1. Leave room entry on the old baseline until final Character Sheet assets exist.
2. Redesign room creation/lobby together with room commands, preset rules and backend authority.
3. Migrate only Layer U: reuse shared Almacén primitives, keep all room/preset state and callbacks caller-owned, and avoid character art entirely for this surface.

## Decisión

Choose alternative 3.

- Create Room uses a paper/sign hierarchy, the existing caller-provided presets and the same create gating.
- Join Room keeps the six-character paste-friendly input inside a clear paper panel and preserves typed input after recoverable errors.
- Lobby presents the grouped room code as a paper notice with copy/share actions separated, player readiness as a roster, and the selected preset using the same reusable visual language.
- Shared `PaperPanel`, `StampBadge`, `TapeMark` and `InkDoodle` primitives carry identity instead of screenshot slices or baked text assets.
- Critical room code, ready status, errors and CTA remain clean and readable; decoration never becomes the only carrier of state.

## Rationale

The migration closes a high-visibility visual gap without broadening authority. Room/preset contracts are already executable and do not need redesign to adopt the visual system. Avoiding character art also keeps this work independent from the source-photo Character Sheet and respects the approved rule that animals are an intentional layer, not permanent chrome.

## Impacto

- Visual continuity from Home → Create/Join → Lobby improves while behavior remains unchanged.
- Room code remains six characters and grouped for display; copy/share remain separate callbacks.
- Join input normalization and recoverable-error retention remain unchanged.
- Preset title/duration/end condition/difference summary remain caller-owned; no final Express/Rápida caps are hardcoded.
- Host/ready/bot markers, start/ready gating, pending/error behavior and disabled explanations remain caller-owned.
- 360 dp / ~130% text-scale behavior remains an executable acceptance target.
- No RoomCommand, routing architecture, Engine, backend, persistence, rules, economy, timers, RNG, authority or deadline semantics are changed.

## DEC-065 / evidence boundary

DEC-065 exact map/economy/card fixture is not required by room entry. No missing canonical fixture content is reconstructed. Test data for presets/players remains explicitly synthetic.

Automated widget/CI evidence can support Layer U only. It does not imply backend room creation/join correctness, multiplayer authority, manual VoiceOver/TalkBack, physical-device behavior, human usability or final Character Sheet acceptance.
