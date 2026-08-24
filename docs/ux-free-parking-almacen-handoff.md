# M1 UX — Estacionamiento Libre Almacén handoff

## Scope

Layer U / presentation-only materialization of Surface 8 from `M1 UX Critical Game Surfaces — Interaction Specification v0.1`, aligned with the current `Almacén uruguayo intervenido + caos familiar ilustrado` visual direction.

The caller remains the source of truth for the confirmed pot amount, resulting balance label, and any source breakdown. This slice does not trigger, calculate, transfer, reset, persist, or reconcile the pot.

## Problema

Estacionamiento Libre had a canonical interaction specification but no executable mobile presentation on `main`. A generic success modal or a client-side `Cobrar` action would overstate Layer U authority and could duplicate a transfer that the specification says is automatic and exactly-once on the authority side. The incomplete DEC-065 fixture also means UX cannot safely invent an exact tax/source breakdown.

## Alternativas

1. Keep relying on the generic `EconomyReceipt` with no surface-specific visual hierarchy. Lowest implementation cost, but the ritual lacks the approved Almacén identity and has no explicit boundary against accidental claim actions.
2. Create a decision modal with `Cobrar` / `Continuar`. Stronger visual moment, but incorrect interaction semantics because Estacionamiento Libre is not a human decision and the effect may already be committed.
3. Create a confirmed-only Almacén event surface that wraps the existing `EconomyReceipt`, has no gameplay CTA, and renders source detail only when supplied by confirmed caller-owned data.

## Decisión

Use alternative 3.

`FreeParkingEventSurface.confirmed` accepts only presentation inputs already confirmed by authority: `confirmedAmount`, optional `resultingBalanceLabel`, and an optional list of `FreeParkingBreakdownItem`. It generates factual receipt copy from the confirmed amount, exposes one live-region summary, and deliberately contains no claim/payment/gameplay button.

The Almacén treatment reuses `PaperPanel`, `StampBadge`, `TapeMark`, `InkDoodle`, semantic palette tokens, and the existing `EconomyReceipt.confirmed`. Source detail is omitted when the caller has no confirmed breakdown; the widget never defaults to or reconstructs `Contribución`, `Patente`, or any other DEC-065 content.

## Rationale

This keeps presentation consistent with the current visual system while preserving the authority boundary. A confirmed-only constructor makes the valid evidence level explicit in the API: the widget cannot represent a speculative pot win. Reusing `EconomyReceipt` keeps money feedback consistent across surfaces instead of adding a second receipt model.

The short scale-in cue is decorative only. `MediaQuery.disableAnimations` reduces it to zero duration, so motion cannot delay the next authoritative state or become part of correctness.

## Impacto

- Estacionamiento Libre now has an executable Almacén presentation surface without adding a human decision.
- Confirmed pot feedback is announced as a single factual live region.
- Optional source detail is caller-owned and therefore cannot fabricate the incomplete DEC-065 fixture.
- No Engine, rules, backend, persistence, RNG, movement, economy calculation, authority, deadline, or exactly-once behavior changes.
- Automated widget evidence can cover confirmed-only presentation, no invented breakdown, no gameplay CTA, semantics, reduced motion, and compact 360dp / ~130% text scale.
- Manual VoiceOver/TalkBack, physical-device motion/haptics, final character art, and human usability remain separate evidence layers and are not claimed by this slice.
