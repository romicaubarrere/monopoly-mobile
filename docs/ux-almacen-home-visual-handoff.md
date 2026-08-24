# M1 UX — Almacén Home visual implementation handoff

## Authority

- M1 Specification Manifest & Evidence Registry v1.2.
- M1 UX/UI & Design System Specification v0.1.
- Visual Direction — Almacén uruguayo intervenido + Character System v0.2.
- M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1.
- DEC-065 remains provenance-incomplete; this implementation uses structural synthetic placeholders only.

## Scope

This change translates the approved `Almacén uruguayo retro + caos familiar ilustrado` direction into reusable Flutter presentation primitives and the Home screen. It changes visual hierarchy, palette and material treatment only.

It does not change gameplay rules, economy, Engine, backend, authority, RNG, deadlines, room lifecycle or final DEC-065 content.

## Decision record

### Problem

The executable Home shell was intentionally low-fi and remained visually generic after the product direction had advanced. It preserved structure and accessibility, but did not yet express the approved warm-paper, commercial-signage, ink/stamp and controlled-chaos language of VR-002.

### Alternatives

1. Keep the generic low-fi Home until every character asset is final.
2. Use the generated visual checkpoint as a flattened background or screenshot-derived UI.
3. Rebuild the approved visual language as responsive tokens and reusable Flutter components now, while keeping source-photo-derived character art as a separate asset step.

### Decision

Choose alternative 3.

### Rationale

It follows the required `Design System → Screen → Component → Asset → State` pipeline, preserves responsive/accessibility behavior, and avoids turning generated references into production screenshots. It also avoids inventing La Maní, Popón or Almendra anatomy before source-photo-derived assets exist.

### Impact

- Semantic palette now follows cream paper, burgundy, bottle green, worn blue, mustard and charcoal.
- Added reusable `PaperPanel`, `AlmacenSign`, `StampBadge`, `TapeMark` and `InkDoodle` presentation primitives.
- Home gains an almacén-style sign hierarchy, printed-material panels and restrained decorative interventions.
- The board preview remains exactly 40 synthetic positions and still exposes one structural semantics summary rather than 40 traversal stops.
- Create/Join keep native controls and minimum touch targets.
- No canonical property, transport, price or card content is introduced.

## Intentional deviations from visual references

- Character illustration is intentionally absent from this implementation. The v0.2 character system requires source photos as anatomical source of truth; generic mascot art would violate that guardrail.
- Decorative density is lower around functional controls than in concept art so CTA, money, connection and board state remain dominant.
- Generated copy/numbers from visual references are not promoted to product data.

## Acceptance evidence target

Named widget checks cover:

- approved Home visual hierarchy;
- explicit DEC-065 synthetic-data boundary;
- 360dp + 130% text-scale renderability;
- Create/Join touch targets;
- existing board summary semantics and disabled-action reason.

Canonical exact-ref CI must be GREEN before merge. This is executable widget evidence, not manual VoiceOver/TalkBack, physical-device, human usability or final character-recognition PASS.
