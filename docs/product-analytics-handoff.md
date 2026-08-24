# M1 Product Analytics executable handoff

Canonical: M1 Specification Manifest & Evidence Registry v1.2; Product Analytics & Timed Playtest Evidence Plan v0.2; M1 Product Analytics Event Contract v0.1; DEC-056.

## Problem

Product telemetry needs stable event names and useful playtest/version context without becoming gameplay authority, leaking identity/private RNG state, or counting transport retries as separate product actions.

## Alternatives considered

1. Call Firebase Analytics directly from screens/ViewModels. Rejected: couples UI to a provider and makes allowlist/privacy/dedupe hard to enforce.
2. Send generic `Map<String, Object>` payloads through a shared analytics helper. Rejected: permits parameter drift and sensitive/free-text leakage by construction.
3. Use a closed typed event contract over an SDK-neutral sink. Selected.

## Decision

`ProductAnalyticsEvent` exposes constructors for the ten canonical events only. Each constructor owns its allowed shape. `ProductAnalytics` performs local logical dedupe and catches sink failures so analytics remains fail-open. `AnalyticsSink` is provider-neutral; `NoopAnalyticsSink` supports disabled telemetry and `RecordingAnalyticsSink` provides executable fake evidence.

Dedupe includes event name, logical event id and result. This deliberately allows `unknown` followed by a reconciled `success`, while repeated confirmed success for the same logical action emits at most once.

Confirmed preset/rules values are caller inputs from confirmed state; `game_start_result=success` rejects missing confirmed preset/rules. No API accepts UID, playerId, room code, auth/App Check tokens, RNG seed/counters/future deck order, full commands, stack traces or free-text comments.

## Impact

Firebase Analytics can be added as an `AnalyticsSink` without changing gameplay/domain contracts. BigQuery/PostHog remain out of M1 acceptance. Analytics delivery is never evidence of authoritative mutation and cannot block commands.

Executable tests cover: exact ten-name allowlist; forbidden shape absence; confirmed StartGame version gate; logical retry dedupe; lost-ACK reconciliation; sink exception fail-open/retry; rating bounds; no-op behavior.

P0 eight-game instrumentation dry run remains later evidence once a stable playable exists; this implementation does not claim balance/fairness/usability evidence.
