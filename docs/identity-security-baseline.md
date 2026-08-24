# Identity and security baseline

M1 uses Firebase Auth anonymous-first. A Firebase `uid` is technical identity only; game authority separately resolves membership `uid -> gameId -> playerId` and revalidates host/actor claims server-side.

The current executable baseline enforces the Firebase ID-token envelope and claims boundary: exact `alg=RS256`, non-empty `kid`, exact project audience and secure-token issuer, future `exp`, non-future `iat` and `auth_time`, bounded non-empty `sub`, plus mandatory signature verification through an injected `IdTokenSignatureVerifier`.

The concrete RS256 provider and Google secure-token certificate fetch/cache are intentionally not implemented in this change. ADR-007 / Dependency Baseline v0.2 selects `dart_jsonwebtoken` only as the cryptographic/parsing primitive behind that boundary; it must be added later with a reproducible lockfile and negative cryptographic suite rather than bypassing the verifier contract.

App Check remains defense-in-depth after Auth and membership correctness. This baseline adds no App Check enforcement, production credentials, cloud workload, gameplay authorization shortcut, or mobile access to RNG seed/counters/future deck state. Token material is not placed in exception messages or observability fields.
