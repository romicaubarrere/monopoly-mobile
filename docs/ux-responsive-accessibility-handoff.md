# M1 UX Responsive & Accessibility Widget Evidence — Handoff v0.1

## Scope

This handoff records presentation-only responsive and accessibility evidence for the current Flutter mobile shell. It is bounded by the canonical M1 Manifest v1.2, UX/UI & Design System v0.1, Accessibility/Motion/Haptics v0.1, NFR-16/17/18/25, and the DEC-065 placeholder boundary.

It does not change gameplay rules, economy, authority, backend, Engine, RNG, deadlines, or the missing exact DEC-065 content.

## Decision — Home board preview semantics

### Problem

The Home screen uses a synthetic 40-position board as structural context. During executable accessibility evidence, the preview did not expose its intended board summary reliably while descendant synthetic tile semantics remained eligible for traversal. For a non-interactive preview, forcing a screen-reader user through 40 synthetic positions creates noise before any actionable decision.

### Alternatives

1. Remove or weaken the semantics assertion and keep the implementation unchanged.
2. Preserve 40 individually announced synthetic tiles in the Home preview.
3. Expose one structural board summary and exclude descendant tile semantics in the non-interactive Home preview, reserving detailed board interaction for the actual game surface.

### Decision

Use alternative 3. `_BoardContextPreview` owns one structural semantic summary and sets `excludeSemantics: true` so its 40 decorative/synthetic descendants are not separate traversal destinations.

### Rationale

The board on Home is context, not a decision surface. A single summary preserves the information that a board exists and that the fixture is synthetic without imposing a 40-item accessibility tax. This is consistent with the M1 interaction principle that critical actions should not require traversing the whole board first, and with the existing executable `BoardTurnSurface` evidence that exposes a board summary without forcing 40 tile labels into semantics.

### Impact

- The Home preview remains visually unchanged.
- Screen-reader semantics expose one structural board summary instead of synthetic per-tile destinations.
- No gameplay state or authority path changes.
- The exact DEC-065 board fixture remains intentionally absent.

## Responsive evidence matrix

The widget matrix covers:

- 360 × 800 dp at 130% text scale.
- 390 × 844 dp at 130% text scale.
- 412 × 915 dp at 130% text scale.
- 430 × 932 dp at 130% text scale.
- Create and Join controls remain at or above `AppSizes.minTouchTarget` (44dp minimum contract).
- Home board preview exposes one structural semantics label and suppresses synthetic tile labels.
- Disabled Roll remains disabled and keeps an explicit visible reason.

## Evidence boundary

These checks are Flutter widget evidence only. They do **not** claim manual VoiceOver/TalkBack PASS, physical-device smoke, multi-device goldens, hardware haptics validation, or a complete accessibility certification.

## DEC-065 boundary

All board content in this evidence remains synthetic/placeholding. No property names, property values, transport strings, card copy, or card effects are invented as substitutes for the missing exact DEC-065 fixture.
