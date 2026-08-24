# M1 UX — Property Detail & Management executable handoff

Canonical: M1 Specification Manifest & Evidence Registry v1.2; Game Rules v1.1; User Flows MVP v0.1; M1 UX Critical Game Surfaces — Interaction Specification v0.1 Surface 2; M1 UX/UI & Design System Specification v0.1; M1 UX Design Token & App Shell Contract v0.1; M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1; M1 UX — Mobile Interaction Feedback & Status Language v0.1; NFR/Quality v1.0; Decision Log DEC-001..065; Traceability v1.2.

## Problema

Property Offer, Auction y Trade ya tenían surfaces ejecutables, pero la gestión de una propiedad propia seguía solo en especificación. Sin un límite executable claro, una futura pantalla podía empezar a decidir legalidad de construcción/venta/hipoteca, calcular economía en cliente o mezclar saldo proyectado con efectivo confirmado.

## Alternativas

1. Crear una pantalla con lógica propia para habilitar/deshabilitar acciones según grupo, mejoras y cash.
2. Integrar gestión de propiedad directamente al futuro GameCommand/ViewModel para que el widget conozca reglas y mutaciones.
3. Materializar una surface presentacional que reciba identidad, economía, nivel de mejoras, acciones ya evaluadas y estados async desde el caller; el widget únicamente renderiza información y emite intents tipados.

## Decisión

Se eligió la alternativa 3.

`PropertyManagementSurface` recibe propiedad/owner/grupo, estado textual del grupo, nivel 0–5, alquiler, próxima mejora/coste cuando exista, estado/valor de hipoteca, efectivo confirmado, efectivo proyectado opcional, una lista de `PropertyManagementActionView` y un `PropertyManagementViewState`.

Las acciones soportadas por presentación son `addMani`, `sellImprovement`, `mortgage` y `unmortgage`, pero su presencia, enabled state, consequence label y disabled reason llegan del caller. La UI no deriva legalidad ni economía desde el nivel o el grupo.

## Rationale

La surface conserva el contrato `confirmed context → intent → pending → confirmed/rejected/stale/uncertain → reconcile` sin introducir reglas paralelas. Mantener `Efectivo confirmado` visual y semánticamente separado de `Proyectado …` reduce el riesgo de feedback optimista. Representar 0–4 Manís y Popón mejora scanability, pero la transición a nivel 5 solo se muestra cuando el snapshot confirmado ya la contiene.

No existe CTA primaria universal en gestión normal: las acciones son pares contextuales y aparecen como controles equivalentes. En contexto Debt, la prioridad y resolución pertenecen a la Debt surface, no a este sheet.

## Impacto

- owner/nombre/grupo y estado completo/incompleto quedan explícitos;
- nivel `0–4 Manís / Popón` tiene texto + señal visual y no depende solo de color;
- alquiler, próxima mejora/coste e hipoteca son datos de presentación, no cálculos locales;
- cash confirmado y proyectado usan contenedores/labels diferentes;
- cada acción muestra consecuencia (`Pagás …` / `Recibís …`) y disabled reason suministrado por caller;
- `pending` deja visible el último estado confirmado, marca solo la acción enviada y bloquea acciones conflictivas;
- `confirmed` muestra receipt/status pero mantiene acciones bloqueadas hasta recibir snapshot fresco;
- `stale`, `rejected`, `uncertain` y `offline` no permiten mutaciones adicionales;
- layout usa `SafeArea` + scroll y target de control de 52dp, compatible con 360dp y text scale aumentado;
- reduced motion sustituye spinner por feedback estático en acción pending;
- semantics agrupan propiedad, mejoras, economía, cash y acciones sin requerir recorrer el board detrás.

## DEC-065

No se hardcodea ningún nombre, importe o grupo del fixture final. Tests usan contenido explícitamente sintético. El color de grupo también llega como dato de presentación. La recuperación exacta 40/4/24+24 sigue en su owner canónico.

## Fuera de scope

- reglas de completar grupo o construir/vender;
- restricciones de balance entre propiedades;
- cálculo de alquiler, coste de mejora, mortgage/unmortgage o cash;
- mutación de ownership/cash/improvements/mortgage;
- GameCommand/ViewModel/backend/Engine;
- debt auto-liquidation;
- timers, RNG o deadline authority;
- assets finales de Maní/Popón.

## Evidence target

Named widget checks:
- `property_management_exposes_confirmed_economy_group_and_improvements`;
- `available_actions_emit_intent_and_caller_disabled_reason_wins`;
- `pending_action_blocks_conflicts_and_preserves_confirmed_vs_projected_cash`;
- `confirmed_state_waits_for_fresh_snapshot_before_new_action`;
- `uncertain_compact_property_management_freezes_and_renders`.

No se emiten nuevos TV IDs. VoiceOver/TalkBack manual, device haptics, multi-device goldens y human usability permanecen fuera del claim hasta evidencia real.