# M1 UX — Trade Builder & Review executable handoff

Canonical references: M1 Specification Manifest & Evidence Registry v1.2; Game Rules v1.1; User Flows MVP v0.1; M1 UX Critical Game Surfaces — Interaction Specification v0.1 Surfaces 4/5; M1 UX/UI & Design System Specification v0.1; M1 UX Design Token & App Shell Contract v0.1; M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1; M1 UX — Mobile Interaction Feedback & Status Language v0.1; NFR/Quality v1.0; DEC-001..065; Traceability v1.2.

## Scope

This branch materializes Trade Builder and Trade Review as Flutter presentation only. Inputs represent currently confirmed/presentable trade data. The surfaces do not create or mutate `TradeState`, validate ownership/cash rules, send commands, resolve deadlines or transfer assets.

DEC-065 integrity remains unchanged. All property/card/economy strings in widget tests are explicit synthetic placeholders.

## Decision 1 — One mobile column, not a desktop two-panel trade

**Problem:** trade naturally compares two sides, but two fixed columns compress asset names, money inputs and accessibility targets on 360–430dp phones.

**Alternatives:** desktop-like side-by-side columns; horizontal paging between sides; vertical `Vos ofrecés` then `Vos pedís` with a bilateral summary.

**Decision:** builder uses one vertical reading order: `Vos ofrecés` → `Vos pedís` → bilateral summary → `Enviar propuesta`.

**Rationale:** keeps thumb targets, text scaling and semantic order stable without hiding one side behind horizontal navigation.

**Impact:** the summary is mandatory context before submit and is phrased explicitly as `Vos entregás … / Vos recibís …`.

## Decision 2 — Selection can prevent obvious UI-invalid input, authority still revalidates

**Problem:** the client needs understandable selection affordances but must not become the source of ownership/cash/trade validity.

**Alternatives:** allow every visible row and rely entirely on backend rejection; encode trade rules in the widget; receive eligibility/disabled reasons as presentation data.

**Decision:** `TradeAssetView` carries presentational availability and optional reason. Cash remains an input field. The caller supplies `draftEmpty/draftValid` rather than the widget calculating domain legality.

**Rationale:** presentation can prevent obvious invalid interaction while preserving server authority and avoiding duplicated game rules.

**Impact:** a future ViewModel maps canonical state into eligibility; submit remains subject to full authority revalidation.

## Decision 3 — Temporary bot cannot expose consent controls

**Problem:** DEC-060 forbids temporary takeover from accepting a trade on behalf of an absent human.

**Alternatives:** let the bot accept balanced deals; auto-reject; preserve proposal state and wait/expire according to authority.

**Decision:** `waitingHuman` disables Accept/Counter/Reject; Accept exposes `El bot temporal no puede aceptar` and the secondary-action semantics explain `Esperando al jugador`. The UI never portrays the temporary bot as consenting.

**Rationale:** a continuity mechanism must not gain human consent authority or private decision rights.

**Impact:** authority decides whether the proposal remains pending, expires or is otherwise closed; this surface only presents that confirmed state.

## Decision 4 — Review distinguishes Recibís from Entregás before any action

**Problem:** symmetric asset lists can make users misread which direction money/properties move, especially at increased text scale.

**Alternatives:** generic `Oferta A/B`; color-coded columns; explicit directional labels and one semantic exchange summary.

**Decision:** Trade Review always leads with `Recibís`, then `Entregás`, using icons plus text and a combined accessibility label.

**Rationale:** direction is transaction-critical and cannot depend on color or spatial assumptions.

**Impact:** `Aceptar` comes only after the exchange and deadline in reading order.

## Decision 5 — Deadline, stale and counteroffer remain authority-bound

**Problem:** proposal expiry and counteroffers can be accidentally implemented as local UI transitions.

**Alternatives:** client countdown closes proposal; client mutates existing proposal into counter; authority supplies state and a counter opens a reversible prefilled builder.

**Decision:** deadline label/progress are presentation inputs. `stale/expired` disable action only when supplied by confirmed state. Counter is a separate user intent; sending it is a new proposal command outside these widgets.

**Rationale:** reconnect must not reset deadlines, stale is not a transport retry, and accepted transfers must remain atomic.

**Impact:** the UI never locally expires, transfers or rewrites a proposal.

## Accessibility and responsive contract

- builder reading order is Offer → Request → bilateral summary → Send;
- review reading order is proposer → Recibís → Entregás → deadline → actions;
- asset selection uses check marker plus semantics, never color alone;
- unavailable assets preserve a reason when supplied;
- action controls use shared >=44dp primitives;
- deadline is not announced every second as a live region;
- 360dp + approximately 130% text scale uses vertical scroll rather than shrinking targets;
- `pending/uncertain/offline` preserve confirmed exchange context and block conflicting mutation;
- reduced-motion behavior comes from shared feedback primitives; no transfer depends on animation.

## Named widget checks

- `trade_builder_exposes_bilateral_summary_in_mobile_order`
- `draft_empty_disables_send_with_reason`
- `pending_send_freezes_asset_selection_and_preserves_summary`
- `trade_review_available_exposes_exchange_deadline_and_actions`
- `temporary_bot_waiting_human_never_exposes_trade_consent`
- `pending_accept_freezes_conflicting_trade_responses`
- `compact_offline_trade_review_remains_renderable_and_safe`

These are UX implementation checks and do not allocate a new TV identifier.

## Evidence boundary

A green Flutter/CI run proves only the presentation/widget assertions exercised by this branch. It does not prove domain trade validation, command idempotency, atomic transfer, real deadline resolution, VoiceOver/TalkBack quality, physical-device haptics, multi-width goldens or human usability.