# GitHub Actions SHA policy coverage — ticket #108 / #13

## Existing policy and defect

[Ticket #108](https://trello.com/c/KrXtnjFF) corrects the existing
`tool/check_ci_policy.sh` check for full commit SHAs. It does not upgrade an
action, change permissions or introduce a new supply-chain service.

The [Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338),
page v173, and [Quality & Test Strategy](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/917505),
page v14, remain canonical. Quality requires executed exact-ref evidence; the
concrete lowercase 40-character SHA rule already exists in the repository guard.
No game rule, decision identifier or canonical registry is changed here.

The original selector only recognized a line starting with `- uses:`. When a
step began with `name:`, its subsequent `uses:` line was not inspected. At the
reviewed base, eight of the nineteen action references were therefore omitted:
six in `pr-review.yml` and Android/emulator plus artifact-upload in `ci.yml`.
All nineteen references were actually pinned. This is a gap in future drift
detection, not evidence of a mutable action or compromised dependency today.

## Checked syntax and value

The guard recognizes direct, unquoted `uses:` mapping keys with or without a
list marker, including a reusable-workflow job using the same block syntax.
The referenced action value must end in a complete lowercase commit SHA. Plain
values and values enclosed in matching single/double quotes are supported.

Validation examines the value itself after removing a trailing whitespace-led
comment and surrounding whitespace/quotes. A SHA appearing only in a comment
cannot make `@main` or a tag pass. Missing, short, mutable and malformed refs,
extra suffixes and unmatched quotes are not accepted as a complete pinned ref.
Local-action and Docker references do not gain an exemption from the existing
SHA requirement in this increment.

This remains a **lexical repository guard, not a full YAML parser or adversarial
workflow sandbox**. It does not resolve aliases, escaped/quoted mapping keys,
flow mappings, generated workflows or every YAML scalar representation. It does
not evaluate whether text matching `uses:` occurs inside a multiline literal.
Such syntax needs explicit review instead of an assumption that this scan covers
it. The existing actionlint job separately validates workflow syntax; actionlint
success is not a substitute for SHA-policy coverage.

The guard also cannot defend against a PR that modifies the guard itself without
review. Full-diff review and protected exact-head checks remain required. The
policy enforces an immutable reference format, not the trustworthiness or
vulnerability status of an action's contents or transitive dependencies.

## Preserved controls and execution

The existing permission scan, one reviewdog PR-write exception, hardcoded
checkout-ref restriction, exit behavior and PASS marker remain unchanged. No
workflow, permission, action SHA, runtime SDK, lockfile or check name is changed.
There is no new dependency, network call, token, deployment or cloud service.

The guard continues to run from the repository-policy job and full local
preflight. New Python standard-library tests are discovered by the existing
Foundation tooling suite. They execute the actual Bash script in temporary
workflow fixtures rather than mocking the selector or running the referenced
actions. Repository source files are not rewritten by those tests.

Regression coverage includes named/unnamed steps, reusable-workflow job syntax,
`.yml` and `.yaml`, full/mutable/short/missing refs, quotes and comment decoys,
and the inherited permission/checkout-ref controls. Each of the nineteen real
references is independently replaced with `@main` in a temporary workflow copy;
every resulting scan must reject it. This checks the current workflow surface,
not all possible GitHub Actions syntax.

Before the fix, the frozen regression file produced 59 passing checks and 67
expected failures: eleven real-reference mutations were rejected and eight
escaped the old selector. After the fix, the identical file passed all 21 test
methods: 120 parameterized subcases plus six independent controls, with no
errors or skips. All nineteen real-reference mutations were rejected. Its
SHA-256 was `57cd3a428b4f82e1197060a3d96bc29892477e8b193fb46b1d750fae93dafddd`
in both runs. The unchanged real workflows also passed the guard.

Independent review then found that a second `uses:` inside a comment could
replace the direct value during greedy prefix extraction. Two additional test
methods reproduced eighteen failures (twelve false acceptances and six false
rejections); the original twenty-one methods remained unchanged. The final
extraction removes only grep's filename prefix, then anchors the mapping key to
the start of the workflow content. The expanded, unchanged regression file
passed all 23 methods, comprising 138 parameterized subcases plus six independent
controls, with zero errors or skips. Its SHA-256 in that RED/GREEN pair was
`5e0d69405909c58373de25a16abc7034196be2a1ce51272ac82751b9e6dbfff2`.

From the repository root:

```sh
python3 -B -m unittest discover -s tool/test -p 'ci_policy_test.py' -v
./tool/check_ci_policy.sh
./tool/preflight.py --format
./tool/preflight.py
env -u DEBUG npm --prefix tool/firebase run emulators:test:all
```

Use the pinned SDKs described in [preflight](dart-preflight.md) and
[the emulator README](../tool/firebase/README.md). No skipped test counts as
PASS. All eight remote checks, including Android evidence, must pass on the
exact final reviewed PR head. Verify the accepted tree and post-main CI before
closing the scoped ticket.

#13 remains open for iOS, runtime/cold-warm/cost and release gates. This policy
coverage correction does not establish M1-wide or release readiness and does
not reconstruct missing DEC-065 content.
