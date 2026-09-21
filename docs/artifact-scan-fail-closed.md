# Artifact scanner diagnostics and failure handling — ticket #115

## Scope and canonical basis

[Ticket #115](https://trello.com/c/GUu75Xm0) corrects the existing source scanner
under [CI quality gates #13](https://trello.com/c/UggPUbKT). It does not add a
new secret detector, change a gameplay rule or inspect a release package.

The [Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338),
page v173, and [Quality & Test Strategy](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/917505),
page v14, were revalidated before implementation. The
[Security Addendum](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1146969),
page v2, requires redaction of private RNG state and sensitive diagnostics under
SEC-18 / TV-15. No canonical registry or missing DEC-065 content is changed.

## Reproduced defects

The credential regex begins with a private-key header's hyphens. The old
`git grep` invocation omitted `-e`, so Git parsed the regex as an option and
returned 129 instead of performing a search. Its conditional discarded stderr
and treated the failure as no match; a clean-looking PASS did not prove that
the credential scan had executed.

The RNG search printed each matching source line. The filename check likewise
printed matching paths. A value on the same line, or sensitive material in a
filename, therefore entered CI output even when the scanner correctly rejected
the input. These are synthetic reproductions, not evidence of a historical
credential disclosure or production incident.

Errors from enumeration and searches also looked like no matches. A real
tracked file with permissions `000` demonstrated an additional Git behavior:
an unreadable-file diagnostic can accompany exit 1, not just a fatal exit code.
Discarding stderr and accepting every 1 would still produce a false PASS.

## Corrected behavior

`git ls-files` must finish with exit 0 before its private, in-memory listing is
inspected. Any nonzero exit aborts with a fixed diagnostic. The filename regex
receives a here-string, not a short-circuit pipeline that can lose a detection
through SIGPIPE. No matching filename is printed.

Content searches pass the pattern with `-e` and retain the existing `-E`, `-I`,
pathspecs and exclusions. They do not use `-q`: selected inputs must be read,
not abandoned at the first match. Matched content is discarded; stderr is
captured privately by the deliberate `2>&1 >/dev/null` redirection order.

A match fails the gate with its existing fixed category message. Only exit 1
with empty stderr is a clean no-match. Other exit codes or a no-match with
diagnostics fail with a fixed scan-error message, without exposing the original
diagnostic. This conservatively rejects warnings as well as errors. Exit 0 and
the existing PASS marker are reserved for successful, nonmatching inspections.

The scanner writes no files, changes no index entries and emits no source lines,
filenames, token values or raw Git errors. Inspect a failing input locally; do
not paste private content into CI, a PR or an issue to diagnose the category.

## Regression evidence

The new standard-library Python suite runs copies of the actual Bash scanner
inside temporary Git repositories, without commits or network access. Synthetic
credential-shaped strings are assembled at runtime. Assertions use fixed
messages and booleans, so expected failures do not print those strings.

The frozen suite contains 21 test methods: 82 parameterized subcases plus eight
standalone cases, totaling 90 scenarios. Before the correction it produced
39 passing scenarios and 51 expected failures, with no errors, skips or timeout:
23 missed credential detections, eight diagnostic disclosures and 20 incomplete
scans incorrectly accepted. Its SHA-256 is
`c12e65f22bee234fa2db7f1168d3ac1ad9b9829458fa8610a03066c84ed08f54`.
After the correction the identical file passed all 90 scenarios in 22.057
seconds, with no failures, errors or skips. The original RED took 20.928
seconds. Neither run changes the test assertions or scanner input fixtures.

Coverage includes all 17 existing credential alternatives, the four executable
roots, six RNG spellings, prohibited filename families, a listing larger than
64 KiB, and a tracked working-tree edit distinct from the index. Benign near
matches, documentation/test exclusions, untracked files, binary content and RNG
outside mobile runtime remain controls rather than new denials.

Normal paths use real Git. Explicit error injection uses a delegating Git stub
only for the selected command, including statuses 1/2/129 and partial output.
An additional real unreadable-file case restores permissions in `finally` and
requires a non-root test user, as on the supported local and hosted runners;
it does not silently skip. Input bytes and the Git index are compared before
and after each scan.

From the repository root:

```sh
python3 -B -m unittest discover -s tool/test -p 'artifact_scan_test.py' -v
bash -n tool/scan_artifacts.sh
./tool/scan_artifacts.sh
./tool/preflight.py --format
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

The tests are discovered by the existing Foundation tooling suite. Keep the
pinned SDKs, real-emulator gate, secret hooks and all eight exact-final-head
remote checks, including Android evidence. Verify the accepted tree and four
post-main jobs before closing this ticket.

## Preserved limits

This is a lexical scan of tracked working-tree source, not a complete security
audit. Existing regex families, case sensitivity, scopes and exclusions remain
unchanged. Untracked files, history, ignored binary contents and paths represented
with Git's quoting/escaping are not newly covered. No APK/IPA contents, arbitrary
encodings, every possible credential or all runtime privacy flows are inspected.

The separate detect-secrets gate and its audited baseline remain unchanged.
No new dependency, allowlist, permission, timeout, service or cloud action is
introduced. #13 remains open for iOS, runtime/cold-warm/cost and release gates;
passing this correction does not establish M1-wide readiness.
