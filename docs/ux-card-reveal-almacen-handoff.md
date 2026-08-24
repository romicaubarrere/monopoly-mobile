# M1 UX — De arriba / De garrón Almacén handoff

## Scope

Presentation-only Flutter surface for the confirmed `De arriba / De garrón` card reveal. This handoff is subordinate to M1 Specification Manifest & Evidence Registry v1.2, M1 UX Critical Game Surfaces — Interaction Specification v0.1 Surface 7, Visual Direction — Almacén uruguayo intervenido + Character System v0.2 / VR-008, and the existing accessibility/motion/status contracts.

It does not define card rules, select a card, execute an effect, inspect RNG state, mutate game state, or reconstruct DEC-065 content.

## Problema

Cards remained an executable UX gap after Home, Auction, Negotiation and A la Cucha migrated to the approved Almacén direction. The generated VR-008 reference is explicitly exploratory: its visual direction is useful, but its card copy is placeholder and its character anatomy is not sufficient to become source-of-truth.

A direct screenshot implementation would also violate the required `Design System → Screen → Component → Asset → State` pipeline and could accidentally bake invented card content or private RNG assumptions into the client.

## Alternativas

1. Wait until the exact DEC-065 24+24 fixture and final source-photo character assets are recovered.
2. Use the generated visual reference as a rasterized final card surface.
3. Build a responsive Almacén card container now, with caller-owned confirmed card data, explicit interaction states and an optional swappable character-art slot.

## Decisión

Use alternative 3.

`CardRevealSurface` receives the confirmed deck identity, public `cardId`, presentation copy, category, optional confirmed impact summary and optional caller-supplied choice actions. It never derives a card from deck position and never owns card effects.

The surface supports automatic cards without action controls, mandatory choice cards with caller-supplied actions, keep-card confirmation, and pending/rejected/stale/uncertain/offline reconciliation states. A choice emits only its caller-provided action ID.

## Rationale

This advances the high-value mobile surface while preserving the evidence boundary. The visual identity lives in paper/sign/stamp/tape containers and not in critical data. Copy and effects remain externally supplied, so replacing synthetic fixtures with the recovered DEC-065 payload does not require redesigning the component.

The character slot is optional rather than filled with a generic dog/cat. This prevents VR-008's known La Maní anatomy problem from becoming executable evidence before source-photo-derived art exists.

## Impacto

- Adds no rule or economy logic.
- Adds no Engine, backend, authority, persistence, RNG or deadline behavior.
- Does not expose seed, counters, future deck order or predictive deck information.
- Does not execute an automatic effect when the reveal opens/closes.
- Does not make generated card copy canonical.
- Keeps the visual layer reversible and rebrandable.
- Uses short reveal motion in normal mode and zero-duration state presentation under reduced motion.
- Preserves a scrollable 360dp mobile layout and the existing minimum control target contract.

## State contract

`confirmed context → reveal/decision available → user intent if required → pending → confirmed/rejected/stale/uncertain → reconcile`

Automatic effects can be displayed after the authority has already confirmed the effect. `actions = []` is therefore a valid and expected state. Choice effects expose only the actions supplied by current presentation state. Pending/uncertain/offline/stale states never enable a second equivalent intent.

`keepCardConfirmed` is a presentation receipt only. It does not move an inventory item locally.

## DEC-065 integrity

Tests deliberately use identifiers and strings such as `CARD-PLACEHOLDER-01` and `[COPY SINTÉTICA DE PRUEBA]`. They are synthetic evidence fixtures only. Exact 24+24 card IDs/copy/effects remain provenance-incomplete and are not reconstructed here.

## Executable checks

The widget suite covers:

- automatic card reveal with no action CTA;
- caller-owned choice action emission;
- pending freeze while preserving confirmed copy;
- keep-card receipt only after confirmation;
- stale/uncertain/offline conflict freeze;
- 360dp with approximately 130% text scaling;
- reduced-motion content equivalence and zero reveal duration.

Manual VoiceOver/TalkBack, physical-device motion/haptics, final source-photo character recognition and human usability remain separate evidence and are not claimed by these widget checks.
