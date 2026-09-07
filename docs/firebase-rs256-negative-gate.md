# Firebase RS256 negative acceptance gate — ticket #20

## Scope and canonical sources

The concrete verifier, certificate fetch/cache and pinned `dart_jsonwebtoken`
`3.4.1` already landed through PR #79. This change completes their negative
regression gate and fixes fresh-cache key rotation; it does not select another
dependency or introduce identity/gameplay policy.

The governing sources are the M1 Specification Manifest & Evidence Registry,
[ADR-007 v0.2](https://personal-romi.atlassian.net/wiki/pages/viewpage.action?pageId=1048723),
and [M1 RS256 Provider Validation — 24 August 2026](https://personal-romi.atlassian.net/wiki/pages/viewpage.action?pageId=2785281).
The validation page is historical research: its statement that the concrete
provider was absent predates PR #79. This handoff records implementation evidence,
not a replacement for those canonical decisions.

## Controlled rotation

`GoogleSecureTokenCertificateCache` follows these rules:

- A cold or expired cache fetches the certificate map. Concurrent callers share
  that fetch. A successful load starts a cache window using Google's positive
  `Cache-Control: max-age`.
- A matching key in a fresh cache needs no network call, even while an
  unknown-key refresh is pending.
- An unknown key in a fresh cache can trigger one extra refresh, as required by
  ADR-007. The budget is consumed **before** network I/O; concurrent misses join
  that refresh. Success or failure does not replenish the extra-refresh budget.
- A successful response replaces the map and expiry using its own `max-age`.
  Further unknown keys fail until the cache expires and a normal load succeeds.
  This bounds extra refreshes without introducing an arbitrary cooldown value.
- A failed extra refresh leaves still-valid matching cached keys usable. An
  expired key is never used after a failed refresh. Missing keys fail closed.

The previous fresh-cache unknown-key behavior rejected rotation without fetching.
A test using the existing real RS256 fixture reproduced that failure before the
fix and passes after it. The existing anti-amplification check is retained, now
asserting one normal load plus at most one extra load for repeated unknown keys.

## Executable evidence

Run from the repository root with the pinned Flutter/Dart SDK on `PATH`:

```sh
./tool/preflight.py
```

For the focused gate, run from `backend/command_service`:

```sh
dart test test/google_firebase_id_token_signature_verifier_test.dart
dart run tool/secure_token_cert_cache_smoke.dart
```

The 61-test provider suite covers:

- Valid RS256 verification with the existing X509 public-key fixture and cache
  reuse; real verification after a newly published `kid` is fetched.
- Rejected `none`, HS256, PS256, RS512 and ES256 headers, including a genuine
  HS256 MAC created with public certificate material, before certificate lookup.
- Missing/invalid `kid`, wrong audience/issuer, expired token, future `iat` or
  `auth_time`, empty/missing/overlong subject, and malformed temporal claim types.
  These tests assert the wrapper's existing rejection codes before crypto;
  modified claims are not presented as freshly signed Firebase tokens.
- A bit-flipped RS256 signature, a changed otherwise-valid subject with the
  original signature, a different parseable RSA modulus inside an X509 envelope,
  and malformed certificate material, all through the real cryptographic adapter.
- Exact `max-age` expiry, one-extra-refresh budget, concurrent misses, budget
  renewal after expiry, cold/expired fetch failures, retained valid cached keys
  during a failed rotation, and malformed/upstream-error responses.
- Typed, redacted identity errors and no `print` output during rejected provider
  calls. This is provider-level evidence, not a claim to have audited every
  deployment log sink.
- A genuinely authenticated fixture identity still rejected independently for
  missing membership, wrong UID, cross-game scope, wrong actor and absent host
  authority. Existing ingress authorization tests remain separate and unchanged.

No private key is generated or added. The existing signed token and public
certificate are synthetic/offline fixtures, not credentials. Mutating a public
modulus exercises signature mismatch, not certificate-chain validation. The
injected clock makes claims and expiry deterministic; no live Google service is
needed by these tests.

## Limits and acceptance

The patch preserves the current strict claim checks and clock behavior; it does
not decide a new clock-skew policy. App Check enforcement, revocation, deployment
credentials, cloud workloads, live-network latency/performance acceptance and a
production security freeze are outside this gate. It changes no membership rule,
RNG visibility, command semantics or unresolved gameplay decision.

The full project security/threat-model work is broader than this provider gate.
Local test success alone is not a release or production-readiness claim. The PR
and Trello handoff must record the exact accepted head, all required workflow
results and merge commit before the scoped ticket is marked Done.
