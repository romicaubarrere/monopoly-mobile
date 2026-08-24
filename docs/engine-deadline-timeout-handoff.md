# M1 Engine deadline timeout policy — handoff

## Problem

Firestore Emulator evidence already proves that `deadline:v1:{decisionId}` can be persisted at most once under concurrent wake-ups, but the durable operation still used a neutral test-harness effect. M1 needs an Engine-owned interpretation of `PendingDecision.timeoutPolicy` before authority can wire a real timeout outcome.

## Alternatives

1. Put timeout behavior directly in the backend transaction handler.
2. Wait until the entire GameState/RulesCatalog/auction/trade/debt Engine exists.
3. Materialize the pure-Dart deadline decision contract first, then integrate it behind the already-proven durable operation.

## Decision

Use option 3.

The Engine owns authority-time deadline eligibility and maps the frozen `timeoutPolicy` to a deterministic action. Persistence remains responsible for the exactly-once operation record and transaction retry. The first slice completes only outcomes that require no further strategic policy (`pass`, `reject`); `botDecide` and `autoLiquidate` remain explicit typed delegations so the system cannot silently invent a bot choice or liquidation sequence.

## Rationale

This keeps gameplay semantics out of the backend while allowing the critical path to advance incrementally. It also preserves the Domain v0.7 stable-transition boundary: delegated work is not reported as completed until the relevant Engine policy actually executes.

## Executable checks

- authority time before deadline => not due / zero effect;
- exact `deadlineAt` => due (inclusive boundary);
- stale decisionId => zero effect;
- deterministic operation ID = `deadline:v1:{decisionId}`;
- `pass` and `reject` are terminal outcomes for the current pending decision;
- `botDecide` remains an explicit bot-strategy delegation;
- `autoLiquidate` remains an explicit deterministic-debt-planner delegation;
- missing deadline never fabricates a timeout.

## Boundary / follow-up

This slice does not implement auction bidder rotation, bot policy, AutoLiquidationPlan, bankruptcy transfer, reconnect/takeover, Firestore integration, canonical RNG or production runtime. After exact-ref unit evidence is accepted, authority must wire the Engine result into the durable deadline transaction; later Engine slices complete the delegated policies and stable consequence chain.
