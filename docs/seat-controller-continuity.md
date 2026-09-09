# M1 seat-controller continuity — ticket #27

## Scope and canonical inputs

This is an incremental Authority authorization fix and a pure semantic gate for
[ticket #27](https://trello.com/c/UI60naEu). It is not acceptance of the whole
timers/AFK policy or an operational takeover implementation.

The decisions come from the M1 Specification Manifest & Evidence Registry and
these canonical Confluence pages, read before implementation:

- [Interaction Timers, AFK & Bankruptcy Policy v0.1](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/917670/Interaction+Timers+AFK+Bankruptcy+Policy+v0.1), version 1;
- [DEC-059/060/061 addendum](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1048829/Decision+Addendum+DEC-059+060+061+timers+continuity+bankruptcy), version 1;
- [Reconnect, Temporary Takeover & Reclaim](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1147153/M1+UX+Reconnect+Temporary+Takeover+Reclaim+Specification+v0.1), version 1;
- [Domain Contracts & State Machine v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1146948/M1+Domain+Contracts+State+Machine+v0.7), version 7;
- [Persistence & Authority Data Model v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041/M1+Persistence+Authority+Data+Model+v0.7), version 7;
- [ADR-010 deadline resolution](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/754066/ADR-010+Deadline+resolution+without+always-on+workers), version 2;
- [DEC-057/058 bot baseline and autosave](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/950517/Decision+Addendum+DEC-057+058+bot+baseline+autosave), version 1;
- [Engine deadline acceptance layers A–D](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/2261020/M1+Engine+Deadline+Transition+Acceptance+Integration+Contract+v0.1), version 1.

No missing DEC-065 content, game economy, bot-strategy constants, new public
command, presence database, background worker or cloud deployment is introduced.

## Implemented authorization correction

Before this change, all seven implemented human game commands could pass their
Authority planner while the actor's seat controller was a temporary bot, even
with `humanReclaimPending=true`. Fourteen negative tests reproduced this.

The three existing human planners now check the current authoritative controller
after authenticated membership and before Engine evaluation. Active permanent
bot seats are also excluded from human input. The canonical rejection is
`controllerNotHuman`; a pending reclaim is not a grant of human control.

This guard is wired into the existing command executor, not only a new helper:

- Roll checks it before constructing/consuming RNG;
- BuyProperty, DeclineProperty, PlaceBid and PassAuction use the human auction planner;
- PayDebt and DeclareBankruptcy use the human debt planner;
- system auction and debt deadlines continue through their separate system paths;
- missing/inactive actors still receive the Engine's existing validation;
- duplicate/collision lookup still precedes new-command evaluation.

A new rejected command persists its safe receipt only: no public-state, RNG,
version or gameplay-event mutation. An exact retry returns that original receipt
even after a later reclaim. Conversely, a lost ACK for an action accepted before
takeover returns its original accepted receipt without a second effect.

## Pure continuity policy, not runtime wiring

`SeatContinuityPolicy` proposes one `SeatControllerState` from trusted Authority
facts. It does not commit or publish that proposal. Its caller must establish
membership, current version, presence and the stable transition boundary.

`ReconnectGraceWindow` freezes one Authority-observed disconnect episode using
the resolved game preset's `reconnectGraceSeconds`. Reevaluation reuses the same
deadline; HTTP retry, foreground and a local countdown cannot reset it.

The semantic behavior follows DEC-060:

- before grace expiry, human control remains;
- at/after expiry, a disconnected blocking seat can propose temporary `balanced`
  control only at a stable boundary;
- an absent nonblocking seat is not forfeited or automatically switched;
- a returning human during an atomic action can propose reclaim intent, not a
  controller switch or cancellation of the bot action;
- at the next stable boundary, a still-present human can reclaim, clearing
  temporary bot metadata;
- permanent bots and inactive players are never converted/reactivated;
- repeated evaluation preserves takeover start time and already-pending intent.

Player identity/kind remains human during temporary takeover. The policy has no
clock reads, private RNG access, bot commands, strategy selection, version bump,
decision extension or persistence side effect. Auction/trade deadlines alone
are not evidence of a disconnect. Existing accepted VP0 decision fixtures remain
unchanged; this does not silently change their timeout policies.

Why this boundary: putting client timers in charge would contradict DEC-060;
pretending a pure proposal is a durable transition would contradict the
Authority ACK contract. The canonical layered acceptance permits checking these
semantics before wiring the transaction/presence adapter, like the existing
[deadline semantic gate](engine-deadline-timeout-handoff.md).

## Reproducible verification

With the repository's pinned Flutter/Dart SDK on PATH:

```sh
cd backend/command_service
dart test test/human_controller_gate_test.dart test/human_controller_transaction_test.dart test/seat_continuity_policy_test.dart
```

- Planner tests: all seven human commands under human control, temporary bot
  control and pending reclaim; membership rejection precedes controller checks;
  system auction/debt timeouts still execute.
- Transaction-callback tests: rejected receipt survives reclaim, lost accepted
  ACK survives takeover without replay, and a conflict retry rechecks controller
  state before committing. The discarded speculative plan never mutates RNG.
- Policy tests: frozen grace and UTC, inclusive expiry, nonblocking absence,
  atomic boundary, repeated evaluations, reclaim, inactive/permanent-bot seats,
  missing/future disconnect observation and inconsistent seat identity.

The callback harness is deterministic unit evidence, **not Firestore concurrency
or durable takeover evidence**. Run the full local gate from the repository root:

```sh
./tool/preflight.py --format
./tool/preflight.py
```

The preflight invokes `./tool/ci.sh`, analysis, tests, architecture/spec checks,
CI policy and artifact scanning. Linux Flutter goldens and Android Tier-1 need
their remote jobs. The two opt-in Dart Firestore integration cases are skipped
without their emulator environment; neither a skip nor the independent Android
smoke is a PASS for those cases.

## Remaining exit criteria — keep #27 open

The policy is not called by the runtime yet. Still required:

1. Authority-confirmed connectivity/disconnect observation and episode lifecycle,
   with safe retry and stable-boundary reconciliation; never trust UI booleans.
2. Atomic durable takeover/reclaim transitions, version/event/receipt semantics,
   concurrency tests and ACK-after-commit proof on the persistence adapter.
3. Separate balanced bot legal-action selection/dispatch for blocking decisions;
   no accepting trades for an absent human, no hidden state, no invented strategy
   parameters. Auction pass and debt auto-liquidation retain their own semantics.
4. Mobile binding of confirmed grace/controller/reclaim state and live recovery
   acceptance; the existing reconnect surface is presentation-only.
5. Canonical human-playtest/calibration evidence. Automated tests do not replace
   complete human games or demonstrate the target interruption/comprehension rates.

This increment does not claim those criteria or move the umbrella ticket to Done.
