# M1 UX — Property Offer executable handoff

Canonical: M1 Specification Manifest & Evidence Registry v1.2; Game Rules v1.1; User Flows MVP v0.1; M1 UX Critical Game Surfaces — Interaction Specification v0.1 Surface 1; M1 UX/UI & Design System Specification v0.1; M1 UX Design Token & App Shell Contract v0.1; M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1; M1 UX — Mobile Interaction Feedback & Status Language v0.1; NFR/Quality v1.0; Decision Log DEC-001..065; Traceability v1.2.

## Problema

Después de materializar board/dados/movimiento, el siguiente punto crítico del turno era la decisión de compra. Sin un contrato executable aislado, una futura screen podía mutar cash/ownership en submit, convertir `No comprar` en navegación local hacia una subasta inexistente o confundir cash proyectado con saldo confirmado.

## Alternativas

1. Resolver compra como diálogo genérico con precio + dos botones.
2. Integrar compra y creación de subasta dentro de la misma implementación junto con GameCommand.
3. Crear una `PropertyOfferSheet` obligatoria y puramente presentacional que reciba datos/estado confirmados y emita solo intents mediante callbacks.

## Decisión

Se eligió la alternativa 3.

La surface recibe identidad/grupo, precio, alquiler base, cash confirmado, cash proyectado, progreso de grupo y un `PropertyOfferDecisionState` de presentación. No interpreta reglas ni calcula valores. `Comprar` es primaria; `No comprar → subasta` es secundaria y únicamente emite intención.

## Rationale

Preserva `confirmed context → decision → intent → pending → confirmed/rejected/stale/uncertain → reconcile`. Diferenciar `Confirmado` de `Proyectado` reduce el riesgo de feedback económico optimista. Mantener la surface congelada ante outcome incierto evita emitir un segundo command equivalente. La subasta solo puede aparecer cuando authority confirme la transición correspondiente.

## Impacto

- anatomy canónica: propiedad/grupo, precio, alquiler base, cash confirmado→proyectado, progreso de grupo y dos acciones;
- insufficient funds deshabilita solo compra y conserva decline cuando sigue siendo opción;
- pending-buy bloquea decline conflictivo;
- pending-decline comunica `Abriendo subasta…` sin abrir AuctionState localmente;
- stale/rejected/uncertain/offline bloquean mutaciones y conservan contexto/reconcile;
- orden de widgets sigue propiedad → economía → consecuencia cash → grupo → Comprar → No comprar;
- señal de grupo está acompañada por `groupLabel`, nunca depende solo de color;
- 360dp + 130% text scale usa scroll y SafeArea;
- confirmed buy/decline cierra esta surface y la siguiente UI se deriva del snapshot confirmado; el receipt económico reutiliza primitives existentes fuera de esta sheet.

## DEC-065

Todos los nombres, valores y colores de grupo llegan como datos de presentación. Tests usan contenido explícitamente sintético. No se hardcodea mapa/economía final.

## Fuera de scope

- BuyProperty/DeclinePurchase GameCommand;
- creación o lógica de AuctionState;
- reglas de fondos/eligibilidad;
- cálculo de precio/alquiler/cash;
- ownership mutation;
- backend, timers, RNG o engine contracts.

## Evidence target

Named widget checks:
- `property_offer_exposes_economy_and_group_without_board_traversal`;
- `insufficient_funds_disables_buy_but_keeps_decline_available`;
- `pending_buy_blocks_conflicting_decline_and_keeps_offer_context`;
- `pending_decline_says_auction_is_opening_without_opening_it_locally`;
- `uncertain_compact_offer_freezes_actions_and_remains_renderable`.

No se emiten nuevos TV IDs. VoiceOver/TalkBack manual, device haptics, multi-width goldens y human usability permanecen fuera del claim.