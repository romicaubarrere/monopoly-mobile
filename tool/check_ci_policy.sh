#!/usr/bin/env bash
set -euo pipefail

status=0

while IFS= read -r line; do
  ref="$(printf '%s\n' "$line" | sed -E 's/.*@([^[:space:]#]+).*/\1/')"
  if [[ ! "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    echo "GitHub Action is not pinned to a full commit SHA: $line" >&2
    status=1
  fi
done < <(grep -RHE '^[[:space:]]*-[[:space:]]+uses:' .github/workflows --include='*.yml' --include='*.yaml' || true)

if grep -RInE '^[[:space:]]*(contents|actions|checks|packages|deployments|id-token|pull-requests):[[:space:]]+write([[:space:]]|$)' .github/workflows --include='*.yml' --include='*.yaml'; then
  echo "Quality workflows must remain read-only unless a job-specific exception is explicitly documented." >&2
  status=1
fi

if grep -nE '^[[:space:]]+ref:[[:space:]]+[^$]' .github/workflows/ci.yml; then
  echo "Reusable quality CI must not hardcode a feature ref." >&2
  status=1
fi

if (( status != 0 )); then
  exit "$status"
fi

echo "CI repository policy: PASS"
