# M1 UX — System Event Toast Almacén handoff

## Scope

Presentation-only reusable feedback for confirmed automatic/system events. Canonical inputs: M1 Specification Manifest & Evidence Registry v1.2, M1 UX/UI & Design System Specification v0.1 (`System/event summary`, `EventToast`), M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1, and Visual Direction — Almacén uruguayo intervenido + Character System v0.2.

This handoff does not define event eligibility, rent/tax amounts, ownership changes, economy, timers, authority, Engine transitions, persistence, RNG, or DEC-065 content.

## Decision record

### Problema

The canonical component inventory includes `EventToast` and the in-game IA includes a state-driven `System/event summary`, but the executable mobile layer only had generic status feedback plus `EconomyReceipt` and a specialized Free Parking surface. Automatic rent/housekeeping/confirmed system events therefore lacked a reusable, non-blocking Almacén presentation primitive.

### Alternativas

1. Keep using ad-hoc `SnackBar`/Material feedback per feature.
2. Reuse the full Free Parking surface for every system event.
3. Add one confirmed-only reusable `SystemEventToast` that receives all factual content from the caller and composes `EconomyReceipt` only when confirmed economy data is supplied.

### Decisión

Use option 3. `SystemEventToast.confirmed` is presentation-only and static by construction. The caller supplies category, title, detail, tone and optional confirmed economy values. It has no timer, no auto-dismiss policy and no gameplay command. Acknowledgement is absent by default and only appears when both label and callback are explicitly supplied.

### Rationale

This keeps low-friction automatic events legible without blocking gameplay, preserves the Almacén visual system through shared paper/stamp/tape primitives, and prevents UX from inventing rent/tax/economy rules or treating local intent as confirmation. A single composed live region avoids duplicate announcements when an `EconomyReceipt` is embedded.

### Impacto

- adds a reusable Layer U primitive under `ui/feedback`;
- automatic events can remain compact and non-modal;
- exact event/economy copy stays caller-owned;
- DEC-065 examples remain explicit `PLACEHOLDER` in tests;
- no changes to Engine, backend, authority, rules, economy, persistence, RNG or deadlines;
- reduced-motion equivalence is trivial because the primitive has no internal animation/timer;
- manual VoiceOver/TalkBack, physical-device and human-usability PASS remain separate evidence.

## Executable acceptance

Widget evidence covers:

- caller-owned confirmed title/detail with no inferred event source;
- exact optional confirmed economy values;
- one composed live-region semantic summary;
- no CTA by default;
- explicit optional acknowledgement with >=44dp target;
- no internal motion/timer;
- 360dp + ~130% text-scale reflow.

## Evidence boundary

A GREEN widget/CI result proves only presentation behavior of this component. It does not prove event correctness, payment/conservation, rent/tax semantics, authority exactly-once behavior, backend integration, final DEC-065 content, Tier-1 accessibility, haptics, or production runtime behavior.
