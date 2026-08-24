# M1 UX — Auction Almacén visual handoff

Status: implementation candidate; must be accepted only after exact-ref CI/review is GREEN and merge is completed.

Canonical sources: M1 Specification Manifest & Evidence Registry v1.2; M1 UX/UI & Design System Specification v0.1; Visual Direction — Almacén uruguayo intervenido + Character System v0.2; VR-005 Auction; Accessibility/Motion/Haptics acceptance specification.

## Boundary

This change is presentation-only. It does not calculate bids, validate economy, select winners, mutate auction state, resolve deadlines, generate RNG, write backend state, or change Engine/rules contracts. `AuctionSheet` continues to receive confirmed presentation data and callbacks from its caller. DEC-065 content remains synthetic/placeholder.

## Decision record

### Problem

The executable Auction surface was functionally complete and authority-safe, but its visual hierarchy still read as generic Material UI. That diverged from the approved `Almacén uruguayo intervenido` direction and VR-005 `remate de barrio`, while the generated/Figma visual checkpoints established warmer paper materiality, dry shadows, signs/stamps and controlled imperfection as the product identity.

### Alternatives

1. Leave Auction visually generic until M6 polish. Lowest immediate risk, but creates growing divergence between approved visual direction and executable surfaces.
2. Apply dense decorative texture and illustration directly to the whole sheet. Strong identity, but risks obscuring current bid, timer, cash and action states.
3. Translate the approved identity through reusable existing primitives and container-level materiality while keeping critical numeric/action information geometrically stable and high contrast.

### Decision

Choose alternative 3. Auction uses the existing Almacén palette and primitives: warm canvas, `PaperPanel`, `StampBadge`, `TapeMark`, dry offset shadows and a `REMATE DE BARRIO` sign. Current bid remains the dominant metric; authoritative deadline, cash, participants, quick increments, custom amount, `Pujar` and `Pasar` preserve their existing interaction/state contracts.

### Rationale

The visual direction explicitly requires roughly 70% functional UI / 20% almacén / 10% controlled chaos during gameplay. Auction is a high-pressure decision surface, so identity belongs mainly in containers and hierarchy, not in the numeric data itself. This keeps the competitive `remate de barrio` character without turning texture into information or making decoration compete with the timer and bid.

### Impact

- Visual: Auction now belongs to the same Almacén system as Home rather than reading as a separate generic Material screen.
- Interaction: no callback, enum, bid input, deadline or async-state behavior changes.
- Accessibility: semantic labels remain intact; decoration remains excluded from semantics; touch targets are unchanged at >=44dp.
- Responsive: existing compact 360dp / ~130% text-scale evidence remains applicable and is re-run by CI.
- Content integrity: no final property names, values, transport strings or card copy are introduced.
- Architecture: no rules/backend/Engine/authority dependency added.

## Named evidence

- `auction_exposes_confirmed_bid_leader_deadline_and_participants`
- `auction_visual_pass_uses_alamacen_hierarchy_without_replacing_semantics`
- `pending_bid_freezes_conflicting_controls_and_keeps_confirmed_bid`
- `rejected_bid_recomposes_from_confirmed_state_and_allows_new_input`
- `passed_player_cannot_reenter_the_same_auction`
- `compact_offline_auction_remains_renderable_and_non_mutating`

## Evidence boundary

Widget/CI success is executable presentation evidence, not manual VoiceOver/TalkBack, physical-device, screenshot-regression, haptics or human-usability PASS. Those remain separate Tier-1/QA evidence.
