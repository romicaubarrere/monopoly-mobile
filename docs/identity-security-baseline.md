# Identity and security baseline

M1 uses Firebase Auth anonymous-first. A Firebase `uid` is technical identity only; game authority separately resolves membership `uid -> gameId -> playerId` and revalidates host/actor claims server-side.

The current executable baseline enforces the Firebase ID-token envelope and claims boundary: exact `alg=RS256`, non-empty `kid`, exact project audience and secure-token issuer, future `exp`, non-future `iat` and `auth_time`, bounded non-empty `sub`, plus mandatory signature verification through an injected `IdTokenSignatureVerifier`.

The concrete RS256 provider and Google secure-token certificate fetch/cache are implemented: they landed in PR #79, including the first real-signature tests. `dart_jsonwebtoken` is pinned to `3.4.1` in `backend/command_service/pubspec.yaml` and the workspace lockfile; it remains a cryptographic/parsing primitive behind `FirebaseIdentityVerifier`, not the policy boundary. The earlier statement that this provider was still pending described the initial baseline, not the current code.

Ticket #20 completes the negative acceptance gate and corrects key rotation against a fresh cache. A `kid` absent from the cached map can trigger one controlled extra refresh, shared by concurrent requests; further unknown keys cannot replenish that budget. A missing/empty token header `kid` is rejected before lookup. See [RS256 negative gate](firebase-rs256-negative-gate.md) for the canonical sources, exact cache semantics, reproducible tests and remaining production limits.

App Check remains defense-in-depth after Auth and membership correctness. This baseline adds no App Check enforcement, production credentials, cloud workload, gameplay authorization shortcut, or mobile access to RNG seed/counters/future deck state. Token material is not placed in exception messages or observability fields.

The later [reconnect receipt actor-binding correction](reconnect-receipt-actor-binding.md)
compares the persisted owner independently of the caller's hash. Game membership
permits the public snapshot, not replay of another actor's private receipt.
