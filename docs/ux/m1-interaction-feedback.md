# M1 UX — Interaction feedback executable handoff

Canonical source: Confluence `M1 UX — Mobile Interaction Feedback & Status Language v0.1` plus Manifest v1.2.

## Problema

The UI already had screen-specific pending/error treatment, but no executable cross-surface contract for distinguishing local press, pending transport, confirmed outcome, stale state, uncertain/lost ACK, offline continuity and disabled eligibility.

## Alternativas

1. Keep feedback logic inside each screen.
2. Build a generic success/error toast layer only.
3. Materialize a small presentation-only state language and reusable controls tied to the authoritative lifecycle.

## Decisión

Use option 3. `InteractionFeedbackState` is presentation state only. `AsyncActionButton` preserves CTA geometry and never communicates success while pending. `InteractionStatusLayer` distinguishes pending, rejected, stale, uncertain and offline. `EconomyReceipt` exposes only a `confirmed` constructor so receipts cannot be instantiated as optimistic pending feedback by accident.

## Rationale

The mobile client must respond immediately to touch without pretending that server-authoritative gameplay has already changed. Reusable primitives reduce contradictory feedback between purchase, auction, trade, debt and reconnect surfaces while keeping domain/transport ownership outside UX.

## Impacto

- Press/pending/outcome remain distinct concepts.
- Pending keeps the action footprint stable and blocks duplicate intent through its presentation contract.
- Disabled actions can retain an accessible reason instead of disappearing.
- Lost ACK uses `uncertain`, not success or generic error.
- Reduced motion swaps the indeterminate spinner for a static progress cue without changing geometry/state.
- Economy receipts are explicitly post-confirmation artifacts.
- No ViewModel, command, backend, routing, rule, economy or RNG implementation is added.

## Evidence target

Widget checks cover:

- `async_cta_preserves_geometry_while_pending`
- `disabled_action_exposes_reason_semantics`
- `economy_receipt_uses_confirmed_snapshot_only`
- `lost_ack_uses_uncertain_not_success_or_error`
- `reduced_motion_keeps_final_geometry_and_state`

These are UX acceptance names, not new TV IDs. Manual VoiceOver/TalkBack, hardware haptics and device usability remain separate Tier-1 evidence.
