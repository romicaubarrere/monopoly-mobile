# M1 UX — Player / Turn / Connection / Bot badges Almacén handoff

## Scope

Layer U / Design System presentation only. Canonical inputs: M1 Specification Manifest & Evidence Registry v1.2; M1 UX/UI & Design System Specification v0.1 component inventory; current A+C / Almacén visual direction; Accessibility, Motion & Haptics acceptance contract.

No rule, Engine, backend, persistence, routing, authority, economy, RNG, timer/deadline, takeover policy or connection detection is implemented here. DEC-065 exact content is not required and is not reconstructed.

## Problema

The canonical component inventory names `PlayerChip`, `TurnBadge`, `ConnectionBadge` and `BotBadge`, while executable surfaces have historically rendered player/turn/network/controller state locally. That creates two UX risks: status can drift between surfaces, and color can become the only carrier of state. Temporary bot coverage also needs language that preserves the human seat identity without implying bot authority beyond caller-supplied state.

## Alternativas

1. Keep every surface-local badge implementation. Lowest immediate code cost, but duplicates semantics, target sizing and visual treatment.
2. Build one fully generic badge with arbitrary colors/icons/text. Reusable, but pushes semantic decisions back to each caller and makes inconsistent or color-only states easy.
3. Add small role-specific presentation primitives over one shared internal badge treatment. Callers own factual labels/state; the Design System owns icon + text redundancy, semantics and Almacén materiality.

## Decisión

Use option 3. `PlayerChip`, `TurnBadge`, `ConnectionBadge` and `BotBadge` are thin presentation primitives. They do not discover state and do not mutate anything. Connection state is passed as a presentation enum; bot temporary/permanent identity is caller-owned; turn/current and self identity are caller-owned.

## Rationale

Role-specific primitives preserve the canonical information architecture and accessibility language without importing game or network policy into Layer U. Icon + visible text means player, turn, connection and temporary-bot state never depend on color alone. Interactive `PlayerChip` opts into a >=44dp target only when a callback exists; read-only instances do not falsely announce themselves as buttons.

## Impacto

- Surfaces can migrate incrementally from ad-hoc HUD labels to shared primitives.
- Current/self/connection/bot distinctions gain consistent semantics and Almacén presentation.
- Temporary bot remains explicitly labelled `Bot temporal`; this component does not activate takeover, reclaim, timers or bot strategy.
- 360dp / ~130% text scale is covered with wrapping/ellipsis behavior rather than adding information density.
- Final character artwork remains outside these status primitives and stays source-photo gated.
- Manual VoiceOver/TalkBack, physical device, final visual recognition and human usability remain separate evidence.

## Executable checks

`apps/mobile/test/status_badges_test.dart` covers explicit icon+text connection states, temporary bot semantics, interactive PlayerChip minimum target and callback, non-color-only self/current semantics, and 360dp / 130% text rendering with PLACEHOLDER content.
