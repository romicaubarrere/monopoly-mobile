# Canonical document mutation guard

Implementation boundary for Trello [#70](https://trello.com/c/1Rw1VhuC) and
[acceptance contract G1–G10 / CFG-GUARD-01..12](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/3735608).
Existing R-21/R-36 only; no new Risk, ADR, DEC, NFR or TV. Confluence and its
promoted sources remain canonical; local snapshots are recovery evidence only.

## Scope and prerequisites

- Python 3.9+ standard library, macOS/Linux (POSIX file locking and permissions).
- Current Confluence Cloud pages in `atlas_doc_format` (ADF), with uniquely named
  top-level H2 sections. No Markdown-to-ADF conversion during mutation.
- Status/evidence maintenance inside explicitly allowed **existing** sections.
  All other sections, the preamble, H2 order/headings and root document metadata
  stay structurally identical. Missing/duplicated sections fail closed.
- Title, page ID, space, status, parent and owner cannot change through this tool.
- A reviewed page-specific policy and an exact UTF-8 candidate body, prepared
  from the captured representation. Policy is an operator-owned allowlist, not
  automatic permission to promote sources or rewrite decisions.
- Snapshots must live outside any Git checkout, on operator-controlled persistent
  storage. The directory is private (0700); snapshot/plan/attempt/outcome files are
  exclusive, private (0600), flushed and fsynced before the next write boundary.
  Do not upload these full-body recovery files as CI artifacts or commit them.
- Existing API credentials supplied through `CONFLUENCE_EMAIL` and
  `CONFLUENCE_API_TOKEN`; never pass credentials as command-line arguments.
  No credential creation, deployment, or live write is part of the test suite.

The HTTP adapter restricts credentials to an HTTPS `*.atlassian.net` origin and
rejects redirects. Requests have a 30-second timeout and bounded responses. It
does not retry PUTs automatically. The implementation follows the official
[v2 page API](https://developer.atlassian.com/cloud/confluence/rest/v2/api-group-page/)
and [version API](https://developer.atlassian.com/cloud/confluence/rest/v2/api-group-version/):
the write sends `version.number = capturedVersion + 1`; historical metadata is
read from the versions endpoint and historical ADF bodies via the page endpoint's
`version` parameter. No assumption is made that version metadata contains a body.

## Prepare a policy without freezing stale operational facts

A policy JSON has exactly these fields (this example is **synthetic**, not a
policy for the live Manifest):

```json
{
  "allowedSections": ["Evidence"],
  "protectedSections": ["Registry", "Sources"],
  "requiredText": ["TV-01..TV-41", "Rules v1.1"]
}
```

All lists must be nonempty and unique. Allowed/protected sections cannot overlap.
Required text is matched in rendered ADF text, not JSON property names or links.
Preserving a marker in an added sentence cannot bypass protection of its source
section. A redacted structural diff records changed section indices and hashes.
The operator still reviews the meaning of changes inside allowed sections.

For the Manifest, lock the promoted-source table, immutable registries,
DEC-064/065, product/rule/authority sections and other sections not owned by the
specific operation. Include all minimum invariants required by the acceptance
contract: TV/NFR/R/ADR/DEC ranges; deadline/provenance boundaries; M0/M1 status;
accepted main; story convergence; critical path; Monte Carlo pause; decision
queue; R-21/R-36/#70; rollback-source reference. Use their **freshly reconciled
canonical values**, not historical main SHAs or critical-path text copied from
the contract's August snapshot. The tool deliberately ships no reconstructed
live Manifest policy. If the current page is missing a required source or
recovery reference, stop for source-reconciled recovery; do not weaken a policy
merely to make a write pass. Gameplay or source promotions require their normal
governance path and are outside this status-only CLI.

## Run

First read the page, prepare/review its policy, and choose a persistent private
snapshot root outside the repository. With credentials already supplied by the
operator's credential mechanism:

```bash
python3 -B tool/canonical_document_guard.py --site https://YOUR-SITE.atlassian.net \
  capture --page-id PAGE_ID --policy /absolute/private/policy.json \
  --snapshot-root /absolute/private/recovery
```

`capture` performs GET only, checks the policy and persists the complete original
page, exact body hash, policy/hash, timestamp, site and tool/Git ref. Its output
identifies the new snapshot directory. Prepare the candidate ADF JSON body from
that snapshot without changing unowned sections, then explicitly apply:

```bash
python3 -B tool/canonical_document_guard.py --site https://YOUR-SITE.atlassian.net \
  apply --snapshot /absolute/private/recovery/canonical-guard-OPERATION \
  --candidate /absolute/private/candidate.adf.json
```

The tool validates identity/invariants/diff, persists the plan, re-reads the
predecessor, and writes an exclusive attempt marker **before** the one PUT.
A changed version, body, title or owner aborts with zero write. The version
message includes a unique operation ID to identify the attempted successor.

An ambiguous ACK or restart uses the same snapshot and exact candidate for
GET-only reconciliation. It never sends the intended PUT twice. If the original
page is unchanged after an uncertain attempt, the result is `notApplied`; rebuild
the operation from a fresh capture only after inspecting current evidence.
Reusing a snapshot with a different candidate fails as `operationCollision`.
Simultaneous local invocations cannot reconcile an in-flight write.

## Verification, rollback and quarantine

- `verified`: exact successor version/operation marker, body hash, metadata and
  invariants match. Historical predecessor/successor evidence is recorded as
  `verified`, `unavailable`, or `mismatch`; unavailability does not masquerade as
  historical proof. A detected historical mismatch quarantines the operation.
- `rolledBack`: an attributed bad write was compensated with the exact captured
  predecessor body at the next version and independently re-read/verified. This
  is a failed intended mutation, not success (CLI exit 1).
- `quarantined`: another writer advanced the page, ownership is uncertain,
  metadata changed, or exact recovery could not be verified. No inferred repair
  or recursive compensation. Preserve all snapshots and request reconciled
  recovery. Quarantine is a **local durable incident result**, not a destructive
  remote status/body change.
- `verificationUnavailable`: the write may have committed. Keep the snapshot;
  the same operation can later re-read without repeating the PUT.

Rollback is attempted only while the bad version still carries our operation
marker, has the expected successor number, preserves identity, and matches a
fresh read immediately before compensation. The compensating PUT also uses the
explicit next version. A concurrent writer is never overwritten to restore an
older body. Lost rollback ACK is re-read, not retried. Process restarts retain the
attempt/failed-write/rollback markers.

`outcome.json` and stdout contain tool/ref, page ID, versions, hashes, operation
class, verification and rollback result—not full bodies, titles, credentials or
raw transport exceptions. Recovery snapshots/plan/failed-write files intentionally
contain full bodies and must remain private. A Git ref with `-dirty` is supporting
local evidence, not accepted exact-commit evidence. Capture/execution refs are
recorded separately; a cached final outcome retains its original execution ref.

## Offline acceptance and limits

```bash
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tool/test -p '*_test.py' -v
./tool/ci.sh
```

The suite covers CFG-GUARD-01..12 plus snapshot failure, local concurrency,
process restart, no-commit ambiguity, failed compensation, source-marker bypass,
metadata mutation, redacted output, duplicate JSON keys, HTTPS/redirect rejection
and explicit REST payload/history behavior. These tests use synthetic documents,
fake version-aware storage and mocked HTTP; no Atlassian call or secret is needed.
Normal CI runs these offline tests without changing gameplay gates or adding
Atlassian availability as a dependency.

This is not a provider-wide permission boundary: direct connector/API writers
can bypass the CLI. A connector without expected-version support cannot be used
as its writer. Live canonical writes and provider integration acceptance still
require appropriate authorization, fresh policy/provenance, and exact-ref
evidence. Do not use the real Manifest as a probe. Keep #70 open until its
implementation/evidence has completed the project's review and acceptance path.
