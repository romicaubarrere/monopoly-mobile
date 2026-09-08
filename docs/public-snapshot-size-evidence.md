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
