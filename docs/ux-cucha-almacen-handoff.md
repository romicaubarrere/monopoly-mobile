# M1 UX — A la Cucha Almacén visual handoff

Status: implementation candidate; accept only after exact-ref CI/review is GREEN and merge is completed.

Canonical sources: M1 Specification Manifest & Evidence Registry v1.2; M1 UX/UI & Design System Specification v0.1; M1 UX Critical Game Surfaces — Interaction Specification v0.1 Surface 6; Visual Direction — Almacén uruguayo intervenido + Character System v0.2; VR-007 A la Cucha; M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1.

## Boundary

This is presentation-only. It does not decide why a player enters or leaves La Cucha, validate doubles, move a token, consume cash/cards, resolve a deadline, generate RNG, write backend state or change Engine/rules contracts. The surface renders only the legal actions supplied by its caller and emits an action ID as user intent. DEC-065 content remains synthetic/placeholder where relevant.

La Maní character art is deliberately not invented. Source photos remain the anatomical source of truth. Until an approved source-photo-derived asset exists, the surface exposes a small replaceable illustration slot labelled as pending rather than substituting a generic dog.

## Decision record

### Problem

VR-007 and the critical-surface specification define A la Cucha as a distinctive mobile decision moment, but no executable surface existed. Two risks had to be avoided at the same time: showing a generic character illustration would violate the approved character-source boundary, while hardcoding all three familiar exit choices would make UX silently encode rules that belong to authority/state.

### Alternatives

1. Wait for final La Maní artwork before creating the surface. This preserves character fidelity but unnecessarily blocks structural mobile UX and async/accessibility evidence.
2. Use a generic dog plus three static buttons. This looks more complete but invents anatomy and may expose choices that are not valid in the current canonical state.
3. Build the Almacén visual shell now with a neutral source-photo placeholder slot and a caller-driven list of currently legal actions, preserving authority-safe pending/reconcile states.

### Decision

Choose alternative 3.

### Rationale

The surface can become executable without claiming unfinished character evidence or duplicating gameplay policy. The visual container, hierarchy, responsive behavior, semantic order and async feedback remain stable when final La Maní artwork is swapped in later. Rendering only caller-supplied actions also matches the explicit rule that fictional disabled choices must not be shown merely because they can exist in another Cucha state.

### Impact

- Visual: `A LA CUCHA` uses warm paper, worn blue, burgundy/mustard accents, `PaperPanel`, `StampBadge`, `TapeMark` and restrained ink decoration from the shared Almacén system.
- Character: a compact replaceable art slot keeps all primary decisions visible; no generic mascot is accepted as character evidence.
- Interaction: action order and availability are caller-owned. The UI emits the selected action ID but does not locally consume cash/card or infer a successful escape.
- Async safety: pending blocks conflicting actions; rejected/stale/uncertain/offline preserve the last confirmed context and expose explicit status language.
- Confirmation: confirmed copy is caller-supplied/presentational and appears only after confirmed state.
- Accessibility: deterministic title → reason → character decoration → confirmed status → state feedback → legal actions; controls retain >=44dp minimum height and character decoration is excluded from semantics.
- Responsive: scroll-safe at compact widths, with the character slot intentionally bounded so legal actions remain the dominant content.
- Motion: pending indicator respects `disableAnimations`; reduced motion changes the cue, never information or geometry.
- Architecture: no dependency on GameState, backend, rules, RNG, economy or authority packages was introduced.

## Named evidence

- `cucha_renders_only_caller_supplied_valid_actions`
- `cucha_action_emits_intent_without_local_consumption`
- `cucha_pending_blocks_conflicting_actions_and_preserves_context`
- `cucha_uncertain_freezes_actions_and_exposes_status`
- `compact_cucha_remains_renderable_at_360dp_and_130_percent_text`
- `cucha_uses_explicit_source_photo_character_placeholder`

## Evidence boundary

Widget/CI success is executable presentation evidence, not manual VoiceOver/TalkBack, physical-device, haptics, final character-recognition, screenshot-regression, final DEC-065 fixture or human-usability PASS.
