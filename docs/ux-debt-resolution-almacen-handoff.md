# M1 UX Debt Resolution Almacén — implementation handoff

Status: proposed executable UX evidence until exact final ref passes CI + PR Review and is merged.

## Authority

This handoff is subordinate to:

- M1 Specification Manifest & Evidence Registry v1.2;
- M1 UX/UI & Design System Specification v0.1;
- M1 UX Critical Game Surfaces — Interaction Specification v0.1, Surface 9;
- Visual Direction — Almacén uruguayo intervenido + Character System v0.2;
- M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1;
- DEC-061 and the current authority/debt contracts promoted by the Manifest.

DEC-065 exact content provenance remains incomplete. Every asset/property/economy example in tests is explicitly synthetic or marked PLACEHOLDER.

## Scope

`DebtResolutionSurface` is presentation-only. It renders caller-owned DebtCase information and emits caller-owned action IDs. It does not calculate liquidation value, determine eligible assets, order liquidation, close a deadline, declare bankruptcy, mutate cash, or persist an operation.

The surface provides:

- near/full-height mobile layout;
- sticky debt summary with amount due, confirmed cash, missing amount and projected cash;
- projected cash visually and semantically distinct from confirmed cash;
- authority-derived deadline label as presentation data only;
- caller-provided liquidation actions with caller-provided gains and disabled reasons;
- confirmed audit trail;
- `available`, `pending`, `rejected`, `stale`, `uncertain`, `offline`, `autoResolving`, `covered` and `insolvent` presentation states;
- sticky `Pagar y continuar` action gated entirely by caller state;
- Almacén materiality through existing `PaperPanel`, `StampBadge` and `TapeMark` primitives;
- reduced-motion-safe pending cue and >=44dp interaction targets.

## Decision record

### Problem

Debt Resolution is a high-stakes, information-dense mobile surface. It must adopt the approved A+C / Almacén direction without obscuring the difference between confirmed and projected money, and without moving debt eligibility, liquidation ordering, timeout fallback, bankruptcy or economy policy into the client UI.

### Alternatives

1. Use a generic full-screen Material list with little product identity. This would be structurally safe but would leave a visible gap in the current Almacén migration and weaken continuity with the accepted Home/Auction/Negotiation/Cucha/Card slices.
2. Reproduce the visual reference as a rich local ledger that calculates a running balance and recommends liquidation actions. This would look expressive but would create optimistic/duplicated authority and could silently encode debt policy in UX.
3. Use an authority-safe Almacén ledger: sticky confirmed summary, projected money explicitly marked as non-confirmed, caller-owned action rows and gains, a confirmed-only audit trail, and a sticky caller-gated pay action.

### Decision

Choose alternative 3.

### Rationale

It follows Surface 9 directly and preserves the visual-direction intensity rule: functional information remains dominant, Almacén materiality lives in containers, and decorative treatment never becomes the carrier of debt state. The same API can later consume a real authoritative DebtCase/AutoLiquidationPlan without rewriting gameplay policy into Flutter.

### Impact

- UX gains an executable Debt Resolution surface aligned with the current visual system.
- Backend/Engine/Rules remain unchanged.
- `cash proyectado` cannot be mistaken semantically or visually for confirmed cash.
- Automatic fallback is represented only after caller state says it is active; the surface never starts it locally.
- Bankruptcy remains a separate authority-confirmed transition/surface; this UI does not infer it.
- Reconnect/uncertain states preserve confirmed context and block equivalent mutation attempts.

## Interaction and evidence boundaries

`confirmed context → available intent → pending → confirmed/rejected/stale/uncertain → reconcile` remains the governing interaction sequence.

The widget never:

- changes cash from a tap;
- derives mortgage/sale values;
- infers whether an asset is legally liquidatable;
- selects an AutoLiquidationPlan;
- decides timeout outcomes;
- declares bankruptcy;
- touches Engine, backend, persistence, RNG or RulesCatalog;
- promotes any synthetic DEC-065 fixture to canonical content.

## Executable checks

The widget suite covers:

1. confirmed vs projected cash separation, including semantics;
2. action intent emits caller action ID only;
3. pending freezes conflicting actions while confirmed cash remains unchanged;
4. caller-owned disabled reason is visible and semantic;
5. automatic-resolution presentation blocks manual controls and preserves confirmed audit entries;
6. `Pagar y continuar` is caller-gated and emits only the caller pay action ID;
7. uncertain outcome blocks equivalent actions and exposes reconciliation status;
8. 360dp / ~130% text scale / reduced-motion-safe renderability.

These are automated widget checks only. They do not claim manual VoiceOver/TalkBack PASS, physical-device PASS, final haptics, human debt-comprehension usability, or durable exactly-once debt integration.

## Acceptance gate

Promotion to accepted automated executable evidence requires the exact final PR head to pass canonical CI and PR Code Review GREEN, followed by merge to `main`. Until then this document describes proposed executable evidence only.
