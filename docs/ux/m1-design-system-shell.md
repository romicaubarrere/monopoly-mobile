# M1 Design System + low-fi mobile shell

Status: implementation checkpoint on `feat/ui-design-system-shell`.

Canonical product/design authority remains Confluence. This file records implementation handoff and executable UX evidence only; it does not redefine gameplay, economy, backend, Engine contracts, timers or DEC-065 content.

## Decision record

Problem → the Flutter scaffold existed with a generic centered `Board Game` label, so the UX spec, reversible `Imprenta barrial` identity and mobile-first shell were not represented in executable code.

Alternatives → keep a generic Material scaffold until gameplay exists; implement a large gameplay mock that risks inventing missing DEC-065 content; or materialize semantic tokens + a deliberately structural shell that uses only synthetic placeholders.

Decision → implement the third option. The UI now consumes semantic design tokens, uses a safe-area portrait shell, exposes Home entry actions and includes a 40-position structural board preview whose content is explicitly synthetic.

Rationale → this creates executable UI evidence without coupling components to unmaterialized content or backend contracts. It also gives later GameShell work stable visual primitives and minimum touch-target behavior.

Impact → `apps/mobile` now owns reusable palette/spacing/radius/size/motion tokens and the M1 light theme. No Engine/backend/package boundary was changed. DEC-065 names, values, transport strings and card copy remain absent by design.

## Implemented contracts

- semantic palette: warm paper canvas/surface, ink text, primary red, teal info, blue focus, danger red, ochre ritual accent;
- base spacing in 4dp increments;
- control/card/sheet radii;
- minimum interactive target 44dp and primary control height 52dp;
- Material 3 theme with semantic component styling;
- safe-area, single-column Home shell;
- compact gutter below 375dp;
- primary `Crear partida` and secondary `Unirse con código` actions;
- 40-position board-context preview with generic semantics;
- disabled roll CTA with explicit reason instead of hidden action;
- no optimistic authoritative money, ownership or game-state mutation.

## Evidence boundary

Widget checks cover shell render, semantic theme wiring, >=44dp primary actions and a 360dp / 130% text-scale composition smoke. These do not constitute full accessibility/device/usability PASS. VoiceOver/TalkBack, goldens at 360/390/412/430dp, larger text scales, reduced-motion runtime behavior and physical Tier-1 evidence remain future gates.

## DEC-065 guardrail

The board preview is intentionally labelled synthetic and displays no final property names, economy values, transport strings or card content. Replace structural placeholders only after the canonical exact-content fixture is recovered and versioned.
