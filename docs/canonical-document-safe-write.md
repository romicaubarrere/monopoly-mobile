# Canonical document safe-write procedure

This procedure protects canonical Confluence sources and the evidence registry from accidental broad overwrites. It is a Product/QA configuration-control guardrail under R-21 and R-36; it does not authorize gameplay, architecture, NFR, risk, ADR, DEC, or TV changes.

## Before mutation

1. Fetch the current canonical page and record its page ID, current version, title, complete body, and timestamp/evidence reference.
2. Snapshot the promoted-source table and immutable registries relevant to the page. For the M1 Manifest this includes TV-01..41, NFR-01..48, R-01..40, ADR-001..010, DEC-001..065, DEC-064, DEC-065, TV-35, TV-39, TV-40, and TV-41.
3. State the intended diff narrowly: which section or operational evidence changes, why it changes, and which sections/identities must remain byte-for-byte or semantically unchanged.
4. Preserve the fetched pre-write body/version as the rollback source. Never reconstruct a rollback body from memory.

## Mutation

5. Apply only the intended change. A status/evidence refresh must not silently promote a new canonical source, redefine an immutable ID, or expand product scope.
6. Use a version message that names the evidence or correction being applied.

## After mutation

7. Fetch the page again immediately.
8. Verify the expected new version exists and the intended section changed.
9. Re-verify promoted canonical sources and immutable ID ranges/assignments against the pre-write snapshot and the repository registry where applicable.
10. If any unintended source, registry, assignment, or unrelated section changed, treat the write as invalid evidence: restore the preserved pre-write body, fetch again, verify restoration, and document the incident before any further promotion.

## Evidence record

For each canonical mutation, retain:

- pre-write page version;
- intended diff/scope;
- evidence references motivating the change;
- post-write page version;
- post-write verification result;
- rollback reference if recovery was needed.

A successful API response is not sufficient proof that a canonical write was safe. Post-write fetch and invariant verification are mandatory.
