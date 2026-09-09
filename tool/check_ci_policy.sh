#!/usr/bin/env bash
set -euo pipefail

status=0

while IFS= read -r line; do
  # Inspect the direct uses value, not a SHA hidden in a trailing comment.
  # This is a lexical block-syntax guard, not a complete YAML parser; see docs.
  # Remove grep's filename prefix before matching only the leading mapping key.
  action_value="$(printf '%s\n' "${line#*:}" | sed -E \
    's/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*//; s/[[:space:]]+#.*$//; s/[[:space:]]+$//')"
  case "$action_value" in
    \"*\"|\'*\') action_value="${action_value:1:${#action_value}-2}" ;;
  esac
  # A relative/local action with a SHA-looking suffix is not a remote pin.
  if [[ ! "$action_value" =~ ^[[:alnum:]][[:alnum:]_.-]*/[[:alnum:]_.-]+(/[[:alnum:]_.-]+)*@[0-9a-f]{40}$ ]]; then
    echo "GitHub Action is not pinned to a full commit SHA: $line" >&2
    status=1
  fi
done < <(grep -RHE '^[[:space:]]*(-[[:space:]]+)?uses:' .github/workflows --include='*.yml' --include='*.yaml' || true)

# Quality workflows are read-only by default. The sole approved write permission is
# job-scoped pull-request access for reviewdog to publish inline analyzer findings.
while IFS= read -r line; do
  if [[ "$line" =~ ^\.github/workflows/pr-review\.yml:[0-9]+:[[:space:]]+pull-requests:[[:space:]]+write[[:space:]]*$ ]]; then
    continue
  fi
  echo "$line" >&2
  echo "Quality workflows must remain read-only unless a narrowly scoped exception is explicitly approved here." >&2
  status=1
done < <(
  grep -RInE '^[[:space:]]*(contents|actions|checks|packages|deployments|id-token|pull-requests):[[:space:]]+write([[:space:]]|$)' \
    .github/workflows --include='*.yml' --include='*.yaml' || true
)

if [[ -f .github/workflows/pr-review.yml ]]; then
  review_write_count="$(grep -cE '^[[:space:]]+pull-requests:[[:space:]]+write[[:space:]]*$' .github/workflows/pr-review.yml || true)"
  if [[ "$review_write_count" -gt 1 ]]; then
    echo "PR review workflow may contain at most one pull-requests: write permission." >&2
    status=1
  fi
fi

if grep -nE '^[[:space:]]+ref:[[:space:]]+[^$]' .github/workflows/ci.yml; then
  echo "Reusable quality CI must not hardcode a feature ref." >&2
  status=1
fi

if (( status != 0 )); then
  exit "$status"
fi

echo "CI repository policy: PASS"
