# M1 Engine deadline durable resolver — handoff

## Problem

The accepted Engine deadline slice proves how a pending decision resolves at authority time, while earlier Firebase Emulator evidence proves that a deterministic `deadline:v1:{decisionId}` operation can be persisted at most once. The gap is executable integration between those two layers without copying timeout policy into the persistence adapter.

## Alternatives

1. Re-encode timeout-policy rules in the Firebase test/runtime adapter. Rejected because backend/persistence would become a second gameplay-rule owner.
2. Add Firestore directly to `game_core`. Rejected because it breaks the pure-Dart Engine boundary and architecture constraints.
3. Add a thin authority planner that calls the canonical Engine and emits a persistence-neutral plan, then make the Firestore adapter consume only that plan. Share contract vectors between the Dart planner test and Firebase Emulator integration test so the JavaScript layer never infers gameplay policy.

## Decision

Use alternative 3.

`DeadlineResolutionPlanner` depends on `game_core`, calls `DeadlineTimeoutEngine`, and translates the result into a transport-neutral plan containing decision identity, expected state version, disposition, action, reason and deterministic operation id. It does not choose a timeout outcome itself.

A shared JSON vector set is executable from both sides. Dart proves each vector is actually produced by the Engine. Firebase Emulator tests consume the same already-decided plan and prove transaction behavior. The emulator adapter does not switch on decision kind or timeout policy.

## Durable acceptance evidence

The integration tests cover:

- captured human ingress `< deadlineAt` remains eligible even when processed later;
- captured human ingress `>= deadlineAt` is `decisionClosed` with zero mutation;
- early deadline wake-up is read-only and persists no system operation;
- decision id and expected state version are revalidated inside the transaction;
- terminal auction `pass` is persisted atomically with one state-version increment and one deterministic system operation;
- two concurrent wake-ups converge on one accepted operation and one duplicate result;
- lost-ACK retry returns the prior persisted action/state version with zero second effect;
- trade timeout persists `reject`, never an invented acceptance;
- stale decision/state plans fail closed with zero writes;
- `delegateBotDecision` and `delegateAutoLiquidation` remain pending and persist no false terminal result.

## State/result boundary

For terminal plans the emulator transaction atomically writes:

- `stateVersion + 1`;
- `pendingDecision: null`;
- an emulator evidence field `lastDeadlineResolution` containing the Engine-produced action/operation identity;
- `games/{gameId}/commands/deadline:v1:{decisionId}` with before/after versions and the same action.

`lastDeadlineResolution` is an integration-evidence field, not a declaration of the final canonical GameState schema. RulesCatalog/GameState work still owns the full stable consequence chain after the timeout result.

## Non-goals

This slice does not implement bot strategy, auto-liquidation sequencing, bankruptcy transfer, canonical RNG, reconnect/takeover, final RulesCatalog/GameState transitions, production Cloud Run wiring, production Firestore schema migration or cost/load evidence. Delegated Engine outcomes therefore remain deliberately unresolved rather than being reported as completed.

## CI impact

`backend/command_service` now has executable tests and is included in the existing `foundation` gate. Required check names and repository protection remain unchanged.
