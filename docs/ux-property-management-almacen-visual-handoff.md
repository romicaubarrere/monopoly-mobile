# M1 UX Property Management Almacén visual pass — handoff

## Canonical basis

- M1 Specification Manifest & Evidence Registry v1.2.
- M1 UX/UI & Design System Specification v0.1.
- Visual Direction — Almacén uruguayo intervenido + Character System v0.2, especially VR-004 Property Sheet.
- M1 UX Critical Game Surfaces — Interaction Specification v0.1, Property Detail / Management.
- M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1.

This slice is Layer U only. It does not change rules, economy, Engine, backend, persistence, RNG, authority, command semantics, deadlines, or DEC-065 content.

## Problem

Property Management already had an executable, authority-safe interaction/state contract, but its containers and hierarchy still used the pre-Almacén generic presentation. After the Property Offer visual migration, moving from offer to management produced a visible identity discontinuity.

## Alternatives

1. Keep the generic management surface until exact DEC-065 property fixtures and final character art exist.
2. Recreate VR-004 as a flattened visual and layer the current actions over it.
3. Recompose the existing surface with shared Almacén material primitives while keeping owner/group/economy/action data caller-owned and Maní/Popón as functional improvement markers rather than character art.

## Decision

Use alternative 3.

The property identity becomes an `EN TU LIBRETA` paper notice with tape and the functional group-color strip. Improvements use a kraft ledger panel, economy uses a paper account block, confirmed/projected cash uses the same `TU CUENTA` language introduced in Property Offer, and actions are grouped as `ACCIONES DE LA LIBRETA`. Existing action buttons and feedback semantics stay intact.

## Rationale

- Keeps the accepted `Design System → Screen → Component → Asset → State` pipeline.
- Creates continuity between Property Offer and Property Management without inventing DEC-065 data.
- Keeps money, mortgage, rent, state and disabled reasons legible while placing texture/materiality on containers.
- Reuses shared `PaperPanel`, `StampBadge`, `TapeMark` and `InkDoodle` instead of introducing one-off decorative widgets.
- Does not treat the Maní/Popón improvement labels as final character art; source-photo Character Sheet work remains separate.

## Impact

Presentation only. Public view models, state transitions, emitted action kinds, caller-owned disabled reasons and confirmed-vs-projected cash semantics remain unchanged. Compact 360dp / ~130% text-scale and reduced-motion behavior remain part of executable evidence.

## DEC-065 boundary

Tests continue to use explicit synthetic property/group/money data. No indexed property names, values, rents, mortgage values, group membership, card copy or transport content is inferred.

## Evidence boundary

Automated widget/CI evidence can establish renderability, semantics, state/action gating, shared design-system use and compact layout. It does not establish manual VoiceOver/TalkBack PASS, physical-device usability, human comprehension, final character recognition, or pixel-perfect parity with VR-004.
