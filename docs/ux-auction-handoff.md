# M1 UX — Auction executable handoff

Canonical references: M1 Specification Manifest & Evidence Registry v1.2; Game Rules v1.1; User Flows MVP v0.1; M1 UX Critical Game Surfaces — Interaction Specification v0.1; M1 UX/UI & Design System Specification v0.1; M1 UX Design Token & App Shell Contract v0.1; M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1; M1 UX — Mobile Interaction Feedback & Status Language v0.1; NFR/Quality v1.0; DEC-001..065; Traceability v1.2.

## Scope

This branch materializes the Auction surface as Flutter presentation only. It consumes confirmed auction presentation data and callbacks. It does not create `AuctionState`, calculate legal bids, resolve deadlines, mutate money or ownership, or send commands.

DEC-065 integrity remains unchanged. Property/economy strings used by widget tests are explicitly synthetic placeholders.

## Decision 1 — Keep the confirmed bid visually authoritative

**Problem:** a bid can be submitted while the client is waiting for an acknowledgement, and a lost acknowledgement can leave the outcome uncertain.

**Alternatives:** optimistically replace the current bid; show the typed amount as if it were accepted; keep the last confirmed bid and freeze conflicting controls.

**Decision:** the headline always represents the last confirmed auction snapshot. `pendingBid` and `uncertain` keep that value visible while mutating controls are blocked.

**Rationale:** this matches the cross-surface authority contract and prevents the UI from claiming money/leader state that the backend has not confirmed.

**Impact:** the eventual ViewModel must pass confirmed bid/leader state separately from the local input draft. Retry/reconcile keeps the same semantic command outside this widget.

## Decision 2 — Deadline is a presentation input, never a local rule engine

**Problem:** the auction needs urgency without allowing a client countdown to decide that a slot or auction ended.

**Alternatives:** local timer closes controls at zero; hide time completely; render authority-derived deadline progress and wait for confirmed state transitions.

**Decision:** `deadlineLabel` and `deadlineProgress` are inputs. The widget labels the deadline as informational and only enters `slotExpired`/`hardCap` when the supplied state says so.

**Rationale:** reconnect/background must not reset or independently resolve the authority deadline.

**Impact:** future wiring derives the display from durable `deadlineAt`; local zero may trigger refresh/wake-up in another layer but never selects an outcome here.

## Decision 3 — Quick increments are input affordances, not auction rules

**Problem:** fast bidding needs thumb-friendly controls, especially in Express, but fixed increments in the UI could accidentally become a rule.

**Alternatives:** fixed hardcoded increments; custom numeric field only; data-driven quick chips plus custom input.

**Decision:** the surface accepts `quickIncrementLabels` and a callback, while retaining the numeric input.

**Rationale:** this keeps speed and accessibility without encoding economy/preset policy in presentation.

**Impact:** callers may provide no increments or different labels. Authority still validates the submitted bid.

## Decision 4 — Passed and expired states are irreversible in this surface

**Problem:** allowing a visually active bid control after confirmed pass/slot expiry creates an invalid re-entry affordance.

**Alternatives:** keep controls active and rely on backend rejection; hide all context; preserve context with disabled actions and explicit reasons.

**Decision:** `passed`, `slotExpired` and `hardCap` preserve auction context but disable mutating controls with semantic reasons.

**Rationale:** users can understand why they cannot act without losing the state of the auction.

**Impact:** the presentation layer does not invent re-entry. Any future rule change must arrive as a different confirmed state, not a local toggle.

## Accessibility and responsive contract

- mandatory surface remains scrollable rather than swipe-dismissible;
- current bid + leader are exposed as one semantic unit;
- participant rows announce label, active/leader/passed/timed-out state and last bid when supplied;
- deadline does not announce every second as a live region;
- quick controls and action buttons use at least the canonical 44dp touch target;
- 360dp + approximately 130% text scale must render without critical overflow;
- color is never the only leader/passed/deadline signal;
- offline/uncertain states block mutation while retaining the confirmed context;
- reduced-motion geometry is inherited from the shared feedback primitives; no auction outcome depends on animation.

## Named widget checks

- `auction_exposes_confirmed_bid_leader_deadline_and_participants`
- `pending_bid_freezes_conflicting_controls_and_keeps_confirmed_bid`
- `rejected_bid_recomposes_from_confirmed_state_and_allows_new_input`
- `passed_player_cannot_reenter_the_same_auction`
- `compact_offline_auction_remains_renderable_and_non_mutating`

These are UX implementation checks and do not allocate a new TV identifier.

## Evidence boundary

A green Flutter/CI run proves only the presentation/widget assertions exercised by this branch. It does not prove timer authority, bidding rules, backend retries, VoiceOver/TalkBack quality, physical-device haptics, multi-width goldens or human usability.