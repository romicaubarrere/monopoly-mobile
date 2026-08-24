# M1 UX Bankruptcy Almacén — handoff

Status: implementation candidate. This document records presentation decisions only; acceptance requires exact-ref CI/review GREEN and merge.

## Canonical basis

- M1 Specification Manifest & Evidence Registry v1.2.
- M1 UX/UI & Design System Specification v0.1.
- M1 UX Critical Game Surfaces — Interaction Specification v0.1, Surface 10.
- Visual Direction — Almacén uruguayo intervenido + Character System v0.2.
- M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1.
- Game Rules v1.1 and User Flows — MVP v0.1 as caller-owned gameplay context.

DEC-065 exact content provenance is incomplete. This slice uses explicit `PLACEHOLDER` fixture content only.

## Decision 1 — distinguish insolvency from confirmed bankruptcy

**Problem.** A bankruptcy surface can falsely tell the player they lost while authority still has an allowed human decision or while the outcome is pending/uncertain.

**Alternatives.**

1. Use one definitive `Perdiste` surface for both insolvency and confirmed bankruptcy.
2. Hide the surface until bankruptcy is final.
3. Model factual pre-confirmation insolvency separately from confirmed bankruptcy.

**Decision.** Use a separate `insolvent` presentation state and reserve `BANCARROTA CONFIRMADA` for the confirmed state.

**Rationale.** This follows Surface 10 and the global authority-visible interaction contract. Presentation cannot promote an unconfirmed transition into a final result.

**Impact.** Pre-confirmation copy remains factual, can expose only a caller-provided legal action, and never renders the confirmed transfer summary.

## Decision 2 — render transfer information only after the atomic outcome is confirmed

**Problem.** Showing cash/assets moving one row at a time can imply partial authoritative mutation even though bankruptcy transfer is atomic outside UX ownership.

**Alternatives.**

1. Animate each transfer optimistically.
2. Show a projected transfer table before confirmation.
3. Render a caller-provided summary only in `confirmed`.

**Decision.** Transfer rows and creditor/bank destination are confirmed-only presentation.

**Rationale.** The UI must not invent transfer ordering, eligibility, liquidation, values or partial progress.

**Impact.** The surface is compatible with any authority-side transfer policy without duplicating it in Flutter. Rows carry confirmed semantics and may contain synthetic placeholders in tests.

## Decision 3 — keep the Almacén identity restrained

**Problem.** Bankruptcy is a high-consequence state; the approved visual system includes humor and animal chaos that could trivialize or obscure the event.

**Alternatives.**

1. Apply the same decorative intensity as Home/results.
2. Remove the visual identity entirely.
3. Keep warm paper, stamps, tape and semantic palette while omitting celebratory character decoration.

**Decision.** Use the third option.

**Rationale.** Visual Direction v0.2 calls for roughly 70% functional UI during gameplay and explicitly requires legible critical information. Surface 10 requires a serious tone.

**Impact.** The surface still belongs to the Almacén system, but hierarchy and comprehension dominate. No character asset is required, so source-photo anatomy is not fabricated.

## Decision 4 — caller-owned optional action

**Problem.** Pre-confirmation bankruptcy-adjacent states may still expose an authority-approved human action, but UX cannot decide which action is legal.

**Alternatives.**

1. Hardcode bankruptcy/retry/liquidation actions in the widget.
2. Never allow any action in this surface.
3. Accept an optional caller-provided `actionId` + label + enabled state and emit only that ID.

**Decision.** Use the third option.

**Rationale.** It preserves presentation flexibility without importing Rules/Engine policy.

**Impact.** Pending/stale/uncertain/offline block conflicting input. `confirmed` never exposes the pre-confirmation action even if stale caller data is supplied.

## Presentation contract

The widget owns only:

- factual insolvency versus confirmed-bankruptcy hierarchy;
- Almacén material presentation;
- confirmed-only creditor/transfer summary;
- continuation/end-state message supplied by caller;
- pending/rejected/stale/uncertain/offline feedback;
- optional caller-owned action intent;
- semantics, scrolling, compact layout and reduced-motion-safe static presentation.

It does not own:

- solvency calculation or bankruptcy eligibility;
- debt fallback or AutoLiquidationPlan;
- creditor/bank selection;
- asset/cash/improvement transfer or liquidation;
- game-end determination;
- Engine, backend, persistence, RNG, economy or deadline behavior.

## Acceptance checks

1. Pre-confirmation insolvency does not render definitive loss copy or confirmed transfers.
2. Confirmed bankruptcy shows caller-provided destination, transfer summary and continuation outcome.
3. Optional action emits only caller-provided `actionId` and causes no local authoritative mutation.
4. Pending/stale/uncertain/offline block the conflicting action and preserve factual context.
5. Confirmed bankruptcy suppresses stale pre-confirmation action data.
6. Confirmed transfer rows expose confirmed semantics.
7. 360dp / ~130% text scale / reduced-motion media setting renders without critical overflow.

Manual VoiceOver/TalkBack, physical-device, final character-recognition and human-usability evidence remain separate and are not claimed by widget CI.
