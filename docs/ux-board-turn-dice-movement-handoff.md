# M1 UX — Board turn, dados y movimiento handoff

Canonical: M1 Specification Manifest & Evidence Registry v1.2; Product Master Plan v0.4; Game Rules v1.1; User Flows v0.1; M1 UX/UI & Design System Specification v0.1; M1 UX Design Token & App Shell Contract v0.1; M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1; M1 UX — Mobile Interaction Feedback & Status Language v0.1; NFR/Quality v1.0; Decision Log DEC-001..065; Traceability v1.2.

## Problema

El shell existente ya demostraba un perímetro de 40 posiciones, pero no existía una surface executable de turno que conectara HUD, dados, CTA, estado pending y movimiento visual sin filtrar reglas o autoridad al cliente. Implementar el gesto de tirar directamente dentro de un screen ad hoc también podía mezclar RNG/dobles/resolución de casillero con presentación.

## Alternativas

1. Convertir el preview de Home en la pantalla de partida y añadir comportamiento allí.
2. Implementar un GameViewModel completo junto con reglas de tirada/movimiento.
3. Crear una `BoardTurnSurface` presentacional que reciba estado confirmado y callbacks, reutilice feedback async y mantenga board/dice/movement separados de Engine/backend.

## Decisión

Se eligió la alternativa 3.

`BoardTurnSurface` recibe player/round/cash/connection, posición actual, valores de dados ya confirmados, destino visual opcional, resumen de movimiento y `InteractionFeedbackState`. No genera números aleatorios, no calcula dobles, no mueve fichas autoritativamente y no resuelve casilleros.

## Rationale

Mantiene el board como contexto mobile-first y hace executable la causalidad UX `acción → pending → snapshot confirmado` sin duplicar reglas. El mismo contrato puede conectarse luego a ViewModel/Repository cuando ese frente lo implemente. También reduce el riesgo de que motion o haptics se conviertan en fuentes implícitas de verdad.

## Impacto

- 40 posiciones estructurales exactas, con contenido sintético mientras DEC-065 siga sin fixture 1:1.
- `DicePair` solo representa valores recibidos; no conoce RNG ni reglas de dobles.
- `AsyncActionButton` bloquea intención duplicada durante pending.
- destino/highlight y `movementSummary` se renderizan solo desde presentation state.
- board expone un resumen semántico único por defecto en vez de forzar 40 labels en la primera traversal.
- 360dp + 130% text scale usa scroll seguro y gutters compactos.
- reduced motion reemplaza la transición de highlight por cambio inmediato, conservando geometría/estado final.
- no se modifican Game Rules, economy, RoomCommand/GameCommand, backend, timers, RNG, persistence ni contracts del motor.

## Evidence target

Named widget checks:

- `board_turn_surface_renders_exactly_40_synthetic_positions`;
- `dice_display_only_renders_confirmed_values_supplied_by_state`;
- `pending_roll_blocks_duplicate_intent_without_hiding_board`;
- `board_summary_does_not_force_40_tile_labels_into_semantics`;
- `compact_board_and_reduced_motion_keep_geometry_renderable`.

No se emiten nuevos TV IDs. Manual VoiceOver/TalkBack, hardware haptics, physical-device motion y human usability permanecen fuera del claim de este ticket.
