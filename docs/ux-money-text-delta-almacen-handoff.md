# M1 UX — MoneyText + MoneyDelta Almacén executable handoff

## Scope

Layer U / Design System only. This slice materializes the canonical `MoneyText` and `MoneyDelta` primitives named by **M1 UX/UI & Design System Specification v0.1**. It does not calculate balances, infer transaction direction, format canonical economy fixtures, mutate money, or decide authority.

DEC-065 remains evidence-gated. Tests use synthetic `PLACEHOLDER` labels only and do not reconstruct property, card, transport, price, rent, tax, or economy payloads.

## Decision record

### Problema

The canonical component inventory requires `MoneyText` and `MoneyDelta`, while accepted `main` had repeated ad-hoc money text styling but no shared primitives under `apps/mobile/lib/design_system`. Repetition increases visual and accessibility drift, especially around tabular numerals, semantic announcements, and positive/negative cues.

### Alternativas

1. Keep money text local to every surface. Lowest immediate change, but preserves drift and duplicates semantics.
2. Create primitives that accept numeric amounts and derive currency, sign, grouping, and direction. More convenient, but would let Layer U own formatting/policy and could accidentally infer economy meaning.
3. Create presentation-only primitives that receive already-confirmed/caller-owned display value, semantic label, and delta tone. The Design System owns typography, spacing, color and redundant icon cues only.

### Decisión

Use alternative 3. `MoneyText` receives a caller-owned `value` plus mandatory `semanticLabel`; `MoneyDelta` additionally receives a caller-owned `MoneyDeltaTone`. Both use tabular numerals. Delta tone is expressed with icon + text + color so color is never the sole channel.

### Rationale

This centralizes the visual/accessibility contract without moving economy, localization, authority, rounding, grouping, or sign policy into UX. It also keeps the component usable while DEC-065 exact fixture evidence is incomplete.

### Impacto

- Shared money typography is now executable and reusable across board, trade, auction, debt, results and receipts.
- Screen readers receive explicit caller-owned labels rather than raw symbol-heavy strings.
- Positive/negative/neutral delta states have a non-color visual cue.
- Tabular numerals reduce layout jitter when values change.
- 360dp + ~130% text scale is regression-covered.
- No rules, backend, Engine, economy, persistence, RNG, routing, analytics or deadlines change.

## Acceptance evidence

Widget coverage must prove:

- caller-owned `MoneyText` value and semantics;
- tabular numeric typography;
- positive/negative/neutral `MoneyDelta` icon cues plus semantics;
- emphasized presentation without value inference;
- safe reflow at 360dp and text scale 1.3.

Merge evidence is valid only for the exact final PR head after canonical CI and PR Review are GREEN.
