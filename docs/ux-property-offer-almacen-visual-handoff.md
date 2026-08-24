# M1 UX Property Offer Almacén visual pass — handoff

## Canonical basis

- M1 Specification Manifest & Evidence Registry v1.2.
- M1 UX/UI & Design System Specification v0.1.
- Visual Direction — Almacén uruguayo intervenido + Character System v0.2, especially VR-004 Property Sheet.
- M1 UX Critical Game Surfaces — Interaction Specification v0.1, Property Offer.
- M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1.

This slice is Layer U only. It does not change rules, economy, Engine, backend, persistence, RNG, authority, command semantics, deadlines, or DEC-065 content.

## Problem

The Property Offer sheet already had executable state and accessibility coverage, but its presentation still read as the pre-Almacén generic Material baseline. That created a visible identity break next to accepted A+C implementations such as Home, Board, Auction, Negotiation, Cucha, Cards, Debt and Results.

## Alternatives

1. Keep the generic sheet until the exact DEC-065 property fixture and final character art exist.
2. Rasterize/copy VR-004 as a visual background and place controls over it.
3. Recompose the existing authority-safe sheet with shared Almacén primitives while keeping all property/economy content caller-owned and final character art out of scope.

## Decision

Use alternative 3.

The sheet now uses the shared `PaperPanel`, `StampBadge`, `TapeMark` and `InkDoodle` vocabulary. The property identity becomes a physical `SE VENDE` notice, group color remains a functional strip, price/rent read as a kraft price card, and confirmed vs projected cash becomes a separate account slip. The primary `Comprar` and explicit `No comprar → subasta` hierarchy remains unchanged.

## Rationale

- Preserves `Design System → Screen → Component → Asset → State` rather than screenshot slicing.
- Advances the approved Almacén identity without inventing canonical property names, prices, rents or group data.
- Keeps critical economy text clean and legible: materiality sits in containers, not in money/state labels.
- Preserves the existing pending/rejected/stale/uncertain/offline behavior and caller-owned authority boundary.
- Keeps the surface rebrandable and independent of Character Sheet assets.

## Impact

Presentation only. Existing Property Offer interaction/state contracts remain intact. The surface gains a consistent A+C visual hierarchy and an explicit widget assertion for shared Almacén material primitives while retaining compact 360dp / ~130% text-scale coverage.

## DEC-065 boundary

All widget examples remain synthetic (`Propiedad sintética`, `Grupo sintético`, synthetic money values). No exact indexed property, transport, card, price, rent or economy payload is inferred from generated references or generic Monopoly knowledge.

## Evidence boundary

Automated widget/CI evidence can demonstrate renderability, semantics, state gating, touch controls and component use. It does not establish manual VoiceOver/TalkBack PASS, physical-device usability, human comprehension, final character recognition, or pixel-perfect parity with VR-004.
