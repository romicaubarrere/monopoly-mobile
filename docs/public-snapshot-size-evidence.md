# Public snapshot size evidence — ticket #19

## Scope and canonical source

[Cost Model & Event Persistence v0.2](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/950383)
(page v2, unchanged when checked) requires `serializedSnapshotBytes` in golden
fixtures. The [Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338)
(page v173) and its promoted specifications remain authoritative. This is an
offline evidence increment, not a new gameplay rule or runtime metric contract.

The committed [metadata report](../backend/command_service/test/fixtures/public_snapshot_sizes.json)
covers **16 full public snapshot occurrences** in two existing synthetic
fixtures. Repeated initial states are retained as distinct fixture paths; these
are not 16 distinct game configurations or production samples.

| Source in `backend/command_service/test/fixtures` | Selected public snapshots | Count |
| --- | --- | --- |
| `bankruptcy_plans.json` | `initialState` and `stateAfter` for `declareA`, `declareB`, `deadline` | 6 |
| `tax_free_parking_plans.json` | Initial and resulting states for tax, debt, collection and zero collection, including both competing tax/collection plans | 10 |

Existing generator-equality tests, also asserted by the new report test, tie
these committed states to the actual Engine/Authority planners. The fixtures
and their generators are unchanged. They use two players and synthetic bounded
board/economy content, not final DEC-065 content. Other fixture files contain
partial projections or private material and are not recursively collected.

## Measurement and privacy boundary

For each explicitly selected path, the tool applies `AuthorityPublicSnapshot`
protocol metadata and recursive privacy validation, then encodes its public
map with the existing `CanonicalDomainJson.encode` used by
`PublicGameState.toCanonicalJson()`. That is compact, sorted-key, integer-only
JSON. **`serializedSnapshotBytes` is its UTF-8 byte length**, and `sha256` hashes
those exact bytes. The hash identifies fixture content, not a command input
fingerprint, RNG commitment or authenticity/security guarantee.

The public boundary is not a full domain decoder. Completeness/provenance is
established by the curated paths and equality with generated Engine snapshots,
not inferred from merely passing protocol validation. Missing/non-object paths,
invalid metadata, private keys and unsupported numeric values fail the report;
there is no silent skip or zero fallback.

Only fixed fixture identifiers, byte counts and hashes are emitted. No snapshot,
command, receipt, UID, token, private RNG sentinel, host path or timestamp is
copied into the report. Nonselected fixture fields cannot affect measurements.
Fixtures must remain synthetic: this tool is not a general-purpose sanitizer
for arbitrary production data. It accepts no input path argument and writes no
file or external service. Its helper lives under test support, not runtime lib.

The report excludes fixture-file indentation, trailing newlines, report metadata,
Firestore document/envelope/index overhead, private game secrets, membership
indexes, HTTP/reconnect envelopes, receipts, headers and transport overhead.
It is not billed storage, total network egress or the entire persisted game.
It does **not** redefine or populate the existing unmeasured runtime
`snapshotBytes=0` or `coldStart=false` defaults.

The separate [reconnect size measurement](reconnect-snapshot-size-metrics.md)
now records the canonical UTF-8 size of a validated public game snapshot in
successful HTTP recovery events. That runtime sample has its own execution and
failure boundaries; this offline report does not fill unmeasured runtime values
or establish production-size distributions.

## Reproduce and review

With the pinned Flutter 3.47.0 / Dart 3.13.0 SDK, from the repository root:

```sh
dart run backend/command_service/tool/report_public_snapshot_sizes.dart
```

The command prints the report to stdout. Review any changed fixture and its
generator first, then deliberately update the metadata golden with the printed
JSON. Neither the command nor tests regenerate accepted golden files in place.
From `backend/command_service`:

```sh
dart test test/public_snapshot_size_evidence_test.dart
```

The tests compare the entire committed report, assert the exact 16 curated
paths, and prove UTF-8 multibyte/escaping behavior, ordering stability,
same-length content hash drift, source immutability, metadata-only output,
privacy rejection, invalid/missing path failures and CLI behavior from both
repository and package roots. The normal `./tool/ci.sh` backend suite runs these
offline tests; no new CI job, dependency, credential or cloud service is needed.
Keep `./tool/preflight.py`, the real Firebase Emulator gate and all eight
exact-head remote checks, including Android Tier-1, before merge.

### Secret scanning of these public hashes

`detect-secrets==1.5.0` flags the report's SHA-256 strings as high entropy.
These are reproducible hashes of the selected synthetic public snapshots, not
credentials. The 16 occurrences contain 14 distinct values; repeated values
share one detector identity. The standard root `.secrets.baseline` records only
those 14 exact identities for this report path and the `Hex High Entropy String`
detector, audited with `is_secret: false`. Its `hashed_secret` fields are the
detector's SHA-1 hashes of the SHA-256 **text**, not snapshot hashes directly;
`is_verified: false` alone would not record a false-positive audit.

Before the required `security / changed-secrets` job loads that baseline,
`tool/secret_baseline_guard.py` compares its complete plugin/filter configuration
with the pinned hook's defaults obtained in an isolated Python subprocess. It
then independently recomputes all 16 public snapshot byte lengths and digests,
requires equality with the entire report, and checks every baseline entry,
including its file, type, first line and audit flag. Unknown fields, duplicate
JSON keys, extra exceptions, changed hashes and weakened settings fail closed.
The Dart generator-equality, privacy and canonical-serialization tests remain
required; the Python guard is not a new runtime/domain serializer or sanitizer.

No detector is disabled, no JSON comment/string pragma or file/line pattern
exclusion is added, and all added/modified files are still scanned. A new
credential in this same JSON or an unapproved hash still fails the real hook.
Even an approved value under a password field remains subject to the keyword
detector. Required integration tests run the actual pinned hook in temporary Git
repositories and fail, rather than skip, if the detector is unavailable. Pure
policy tests also run in Foundation without installing a Python dependency.

The CI job installs the pinned detector in a fresh virtual environment under
`RUNNER_TEMP` and places that interpreter on `GITHUB_PATH` for subsequent steps.
An isolated import smoke check runs before publishing that path. A user-site
pip install is insufficient: Python's intentional `-I` mode excludes user-site
packages, which previously made the Linux job reject the baseline as
`pinnedDetectorUnavailable`. The fix changes the installation location, not
the isolation or detector configuration; see Python's [isolated-mode](https://docs.python.org/3/using/cmdline.html#cmdoption-I)
and [virtual-environment](https://docs.python.org/3/library/venv.html) documentation.

To reproduce the security checks in an environment with the existing pinned
`detect-secrets==1.5.0` dependency installed:

```sh
python -B tool/secret_baseline_guard.py
python -B -m unittest discover -s tool/security_test -p '*_test.py' -v
detect-secrets-hook --baseline .secrets.baseline -- backend/command_service/test/fixtures/public_snapshot_sizes.json
```

When a reviewed fixture legitimately changes, first verify its generator and
update/review the report as above. A baseline update is a separate explicit
false-positive audit of those reproducible public hashes, never an automatic
`scan --baseline` step in CI. A changed line/removed finding that makes the hook
rewrite the baseline returns exit 3 and still fails the job; it is not silently
accepted. The guard's fixed 16-occurrence/14-identity scope also requires explicit
review if the curated coverage or duplicate-state structure changes.

## Interpretation and remaining evidence

This report currently spans **1,668–2,186 bytes**. Every selected snapshot is
below 100 KiB (102,400 bytes), the Cost Model's normal range. This does not prove
maximum board/save size, late-game growth, 6-human behavior, production p50/max
or workload headroom. A reviewed fixture change can legitimately change these
numbers; golden equality is a drift review gate, not a hard size budget.

The source also calls for observing 100–256 KiB and opening a risk/ADR above
512 KiB. It does not fully specify the intervening band or every exact boundary;
this tool reports numbers without inventing a complete classifier or new
hard-fail thresholds. No padded synthetic state is presented as real load data.

[Ticket #19](https://trello.com/c/dk2nQOYj) stays En curso. Runtime snapshot-size
boundaries, GET/pre-ingress telemetry, client reconnect/takeover traces,
cold/warm p50/p95, NFR-48 and real limits/cost remain separate work. No deploy,
billing activation, new service or canonical DEC/NFR/TV ID is introduced;
`minInstances=0` and emulator-first remain unchanged.
