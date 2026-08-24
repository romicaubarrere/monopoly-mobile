# M1 UX Results Almacén — handoff

Status: proposed executable UX presentation until exact-ref CI + PR Review are GREEN and merged.

## Authority

- M1 Specification Manifest & Evidence Registry v1.2.
- User Flows — MVP v0.1, UF-15 Fin Express/Rápida and UF-16 Fin Clásica por bancarrota.
- Game Rules v1.1 — M1-aligned, including deterministic ranking/tie semantics.
- M1 UX/UI & Design System Specification v0.1.
- Visual Direction — Almacén uruguayo intervenido + Character System v0.2.
- M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1.
- NFRs/SLOs v1.0 and Quality/Test Strategy v1.0.

DEC-065 remains provenance-incomplete. Every game-data example in this slice is caller-owned or explicit `PLACEHOLDER`; no final board, economy, transport or card fixture is reconstructed here.

## Problem

The product already had executable presentation for the main in-game decision surfaces, but the terminal experience still lacked a real mobile Results surface. A generic ranking screen would create three risks:

1. showing a winner/ranking before authority has confirmed `game_end`;
2. calculating Net Worth, ordering or tiebreak rules in UI code;
3. visually breaking the approved A+C / Almacén direction at the moment with the highest emotional payoff.

The Results surface must therefore be expressive without becoming authoritative.

## Alternatives

### A. Calculate ranking and Net Worth in Flutter

Rejected. It duplicates Game Rules/Engine responsibility and could diverge under retries, reconnect or future rule changes.

### B. Show an optimistic winner while final state is pending

Rejected. A pending/stale/uncertain/offline close must not expose a provisional economic result as fact.

### C. Render only confirmed caller-owned results, with explicit pre-confirmation states

Selected. Flutter receives mode, end reason, ordered participant rows, tie flags and Net Worth breakdown as presentation input. It renders them only in `confirmed`; all other states preserve context and explain reconciliation without exposing a ranking.

## Decision

Implement `ResultsSurface` as a presentation-only terminal surface with:

- `pending`, `stale`, `uncertain`, `offline`, `confirmed` states;
- confirmed mode + end-reason labels provided by caller;
- confirmed ordered ranking provided by caller;
- per-participant confirmed Net Worth and breakdown: cash, properties, mortgage debt, improvements;
- explicit `isSharedPlace` presentation rather than UI tiebreak logic;
- caller callbacks for `Revancha`, `Nueva partida`, `Salir`;
- no ranking or terminal CTAs before confirmed close;
- Almacén paper/stamp/tape materiality while keeping result data highly legible;
- semantics summary per ranking row;
- scrollable content + fixed terminal action area;
- 360dp / ~130% text scaling and reduced-motion-safe static presentation.

## Rationale

UF-15 says server calculates Net Worth v1, applies Rules v1 tiebreakers and sends the same ranking to every player. UF-16 likewise requires a confirmed `game_end` before the final summary. The UI's safest and clearest contract is to consume that confirmed result rather than reconstruct it.

The visual treatment follows the current Almacén direction: identity lives in the container/materiality, not in critical numbers. Results may carry more personality than normal gameplay, but information remains the dominant layer.

## Impact

Positive:

- closes a major terminal-flow UX gap for Fast and Classic modes;
- prevents optimistic winner/ranking leakage;
- keeps ranking/tie/economy logic outside Flutter;
- preserves consistent A+C visual language;
- supports responsive and semantic widget evidence.

Trade-offs:

- this slice cannot prove Net Worth correctness, ranking correctness, tiebreak correctness or `game_end` correctness;
- `Revancha` participant reuse semantics remain caller/router responsibility;
- human celebration quality, device accessibility and character recognition still require manual evidence.

## Presentation contract

`ResultsSurface` may prove only:

- confirmed/unconfirmed presentation gating;
- exact display of caller-provided ranking and breakdown labels;
- shared-place semantic labeling;
- callback emission for terminal actions;
- pending/stale/uncertain/offline reconciliation language;
- responsive/accessibility behavior at widget layer.

It may not prove or implement:

- Net Worth formula;
- ranking order;
- tiebreak evaluation;
- game-end eligibility or final round boundaries;
- bankruptcy correctness;
- rematch participant/state reuse;
- navigation/backend/Engine/persistence/economy/RNG behavior.

## Test matrix

Named widget checks:

- `unconfirmed_result_hides_ranking_and_exit_actions`;
- `confirmed_result_renders_caller_owned_ranking_and_breakdown`;
- `shared_place_is_exposed_without_local_tiebreak_copy`;
- `confirmed_actions_delegate_navigation_intent_to_caller`;
- `offline_result_keeps_confirmed_ranking_hidden`;
- `confirmed_empty_ranking_has_factual_fallback`;
- `compact_results_render_at_360dp_and_130_percent_text`.

## Evidence boundary

Until exact final head has canonical CI + PR Review GREEN and merges, this file is handoff/proposed executable evidence only. Widget GREEN does not imply manual VoiceOver/TalkBack, physical-device, human usability, Net Worth, Engine or authority PASS.
