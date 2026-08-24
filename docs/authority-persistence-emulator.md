# Authority persistence emulator evidence

This M1 evidence is emulator-only and creates no cloud workload.

The Firestore integration test proves the persistence boundary expected by the canonical M1 authority model:

- room state and command record are written in one Firestore transaction;
- an existing identical command is classified as duplicate and produces zero writes;
- a reused commandId with different semantic identity is classified as collision and produces zero writes;
- stale expectedVersion produces zero writes;
- requestReceivedAt is supplied by ingress and persisted unchanged;
- inputHashVersion is persisted as version 1;
- logical read/write operation counts are surfaced by the harness for observability evidence.

This test does not claim production deployment, cloud cost, deadline worker behavior, RNG implementation, or gameplay-rule correctness. Game rules remain owned by the canonical Game Engine and are not implemented here.
