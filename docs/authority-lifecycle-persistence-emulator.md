# Authority lifecycle persistence — emulator evidence

This evidence is local/emulator-only and creates no cloud workload.

Canonical scope: Manifest v1.2, Persistence v0.7, Quality/Test Strategy v1.0, Quality Addendum TV-35..41, ADR-010.

## What the test proves

- **TV-40:** a `roomCodes/{codeHash}` document can remain physically present after logical expiry; authority lookup still returns `roomUnavailable` and performs zero membership mutation.
- **TV-41:** two concurrent Firestore transactions attempting to reclaim the same expired `codeHash` converge on exactly one active mapping. The losing candidate does not leave a room document behind.
- **Deadline early wake-up:** `authorityNow < deadlineAt` is read-only/no-op; deadline and game state remain unchanged and no system operation is persisted.
- **Deadline concurrency:** two concurrent wake-ups for deterministic `deadline:v1:{decisionId}` persist one system operation and one test-harness state effect.

## Important boundary

The deadline test deliberately uses a neutral `deadlineEffectCount` test-harness mutation instead of implementing a Monopoly timeout outcome. It proves Firestore transaction/idempotency behavior only. Actual timeout policy, automatic chain, debt/takeover behavior and RNG consumption remain owned by the canonical Engine/authority integration.

This evidence does not claim:

- production/cloud persistence;
- StartGame atomicity;
- gameplay-rule correctness;
- RNG at-most-once;
- reconnect/takeover/debt continuity;
- physical TTL correctness or dependency.

TTL remains housekeeping only; logical expiry is authoritative.

## Acceptance interpretation

If exact-ref CI executes this file through the Firebase emulator job and is GREEN, TV-40 and TV-41 may be promoted from pending to executable emulator PASS because their canonical criteria are persisted expired state and transaction concurrency. Deadline results may be recorded as supporting ADR-010 durable-operation evidence, but do not close the full deadline/Engine gate until the real authority transition is wired.
