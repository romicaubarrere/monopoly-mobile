# M1 UX Board Almacén visual handoff

## Scope

Presentation-only visual migration of the existing `BoardTurnSurface` and `DicePair` to the current **Almacén uruguayo intervenido + caos familiar ilustrado** direction.

Canonical inputs: M1 Specification Manifest & Evidence Registry v1.2; M1 UX/UI & Design System Specification v0.1; Visual Direction — Almacén uruguayo intervenido + Character System v0.2 / VR-003; Accessibility, Motion & Haptics acceptance specification; existing Board turn/dice/movement executable evidence.

DEC-065 remains provenance-incomplete. This slice keeps exactly 40 synthetic structural positions and does not introduce property names, prices, groups, transport strings, card content or economy values.

## Decision record

### Problem

The executable board already proved the vertical 40-position geometry, confirmed dice presentation, movement summary, pending roll protection, semantics and compact/reduced-motion behavior. Its visual language, however, still read as generic Material UI and no longer matched the approved A+C direction already materialized on Home, Auction, Negotiation and later decision surfaces.

### Alternatives

1. Leave Board visually generic until DEC-065 and character art are complete.
2. Reproduce VR-003 literally, including generated details and screenshot-like decoration.
3. Migrate only the stable presentation layer now: reuse shared Almacén primitives/tokens, keep all game data caller-owned, retain synthetic board positions and preserve the existing interaction/authority contract.

### Decision

Choose alternative 3. The Board receives warm paper/kraft materiality, dry printed borders, tape/stamp accents, a storefront-style turn HUD, a restrained central board sign and physical-table dice treatment. Functional information remains visually cleaner than decorative containers.

### Rationale

The Board is a stable, high-frequency surface and was explicitly listed as an open A+C migration gap. Its geometry and state contract already exist, so the visual layer can converge without waiting for missing DEC-065 content or touching gameplay ownership. Reusing `PaperPanel`, `StampBadge`, `TapeMark`, `InkDoodle` and semantic palette tokens keeps the design system coherent instead of slicing generated screenshots.

### Impact

Positive:

- Board now belongs to the same visual family as the accepted Almacén surfaces.
- 40-position structural geometry, confirmed-state semantics and roll protection remain unchanged.
- HUD can wrap at compact widths and elevated text scale instead of forcing a desktop-like single row.
- Dice acquire tactile identity without making animation or decoration carry state.

Trade-offs / limits:

- Tiles remain neutral structural placeholders until the provenance-backed board definition exists.
- No character asset is inserted; source-photo Character Sheet remains a separate owned task.
- This is widget/CI presentation evidence only, not manual device, VoiceOver/TalkBack, physical haptics, final visual-recognition or human-usability PASS.
- VR-003 is used for hierarchy and identity, not as a pixel-perfect screenshot contract.

## Preserved authority boundaries

The UI consumes only caller-supplied confirmed/presentation values. It does not roll dice, move a token, resolve doubles/Cucha, resolve a tile, mutate cash/ownership, decide a deadline, generate RNG or create commands. No Engine, backend, persistence, rules, economy or authority contract is changed.

## Acceptance evidence target

- exactly 40 `board-tile-*` positions;
- confirmed dice semantics remain caller-owned;
- pending roll cannot emit duplicate intent and board context stays visible;
- one summary semantics node avoids a forced 40-tile traversal;
- shared Almacén material primitives are used rather than local screenshot-like chrome;
- 360 dp + ~130% text scale remains overflow-free;
- reduced motion produces zero-duration tile highlight transitions;
- canonical formatter/analyzer/widget/architecture/security CI and PR Review must be GREEN on the exact accepted head before merge.
