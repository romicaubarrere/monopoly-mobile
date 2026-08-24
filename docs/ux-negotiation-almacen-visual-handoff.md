# M1 UX — Negotiation Almacén visual handoff

Status: implementation candidate; accept only after exact-ref CI/review is GREEN and merge is completed.

Canonical sources: M1 Specification Manifest & Evidence Registry v1.2; M1 UX/UI & Design System Specification v0.1; Visual Direction — Almacén uruguayo intervenido + Character System v0.2; VR-006 Negotiation; Accessibility/Motion/Haptics acceptance specification.

## Boundary

This is presentation-only. It does not validate trade eligibility, move assets or cash, resolve deadlines, grant consent, generate RNG, write backend state or change Engine/rules contracts. `TradeBuilderSurface` and `TradeReviewSurface` continue to receive caller-provided confirmed presentation data and callbacks. DEC-065 content remains synthetic/placeholder. Free chat is not introduced.

## Decision record

### Problem

The executable negotiation flow already had the required bilateral information architecture and safe async/consent states, but it still read visually as generic Material UI. VR-006 establishes a more specific two-sided negotiation baseline with visible property/item cards, while the approved product identity uses warm paper, signage, stamps and dry printed materiality.

### Alternatives

1. Keep the generic surface until final visual polish. Lowest short-term change, but increases drift between approved visual direction and executable UI.
2. Force literal two-column layout at every mobile width. Closest to the concept image, but produces narrow columns at 360–430dp and is fragile at ~130% text scale.
3. Preserve the two-sided comparison model while making it responsive: each side is an explicit ledger panel, stacked on compact mobile in canonical reading order, with the bilateral summary/review preserving immediate `entregás` vs `recibís` comparison.

### Decision

Choose alternative 3.

### Rationale

The product is mobile-first and the accessibility contract outranks screenshot geometry. `Vos ofrecés → Vos pedís → balance` remains the deterministic traversal order, while differentiated paper panels and accent rules preserve the visual two-sided model. This keeps VR-006's comparison intent without compressing property names, money fields or assistive text into ~160dp columns.

### Impact

- Visual: negotiation now uses the same Almacén language as Home/Auction through `PaperPanel`, `StampBadge`, `TapeMark`, warm canvas, kraft summary and dry borders.
- Interaction: no public state enum, callback, selection, cash input, deadline or consent behavior changes.
- Consent: `waitingHuman` still never exposes Accept/Counter/Reject for a temporary bot.
- Accessibility: semantic bilateral summaries and deadline wording are preserved; decoration is excluded from semantics; controls retain >=44dp minimum height.
- Responsive: side panels stack at compact widths rather than forcing a literal two-column grid; this is an intentional mobile adaptation of VR-006.
- Content integrity: Properties/Money/Cucha-card eligibility remains caller/domain-owned; no exact DEC-065 fixture is invented.
- Architecture: no rules/backend/Engine/authority/RNG dependency added.

## Named evidence

- `trade_builder_exposes_bilateral_summary_in_mobile_order`
- `trade_visual_pass_uses_almacen_ledger_hierarchy_without_changing_semantics`
- `draft_empty_disables_send_with_reason`
- `pending_send_freezes_asset_selection_and_preserves_summary`
- `trade_review_available_exposes_exchange_deadline_and_actions`
- `temporary_bot_waiting_human_never_exposes_trade_consent`
- `pending_accept_freezes_conflicting_trade_responses`
- `compact_offline_trade_review_remains_renderable_and_safe`

## Evidence boundary

Widget/CI success is executable presentation evidence, not manual VoiceOver/TalkBack, physical-device, screenshot-regression, haptics, final DEC-065 fixture or human-usability PASS.
