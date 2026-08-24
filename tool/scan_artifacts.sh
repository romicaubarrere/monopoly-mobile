#!/usr/bin/env bash
set -euo pipefail

status=0

forbidden_files='(^|/)(\.env($|\.)|serviceAccount[^/]*\.json$|google-services\.json$|GoogleService-Info\.plist$|[^/]+\.(p8|p12)$)'
if git ls-files | grep -E "$forbidden_files"; then
  echo "Forbidden credential/environment artifact is tracked." >&2
  status=1
fi

secret_pattern='-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|AIza[0-9A-Za-z_-]{35}|ya29\.[0-9A-Za-z._-]+|gh[pousr]_[0-9A-Za-z]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|"private_key"[[:space:]]*:'
if git grep -nEI "$secret_pattern" -- apps packages backend .github ':!**/*.md' ':!**/test/**' ':!**/test_*' 2>/dev/null; then
  echo "Potential credential/private key material found in executable repository surfaces." >&2
  status=1
fi

private_rng_pattern='(rngSeed|rng_seed|futureDeckOrder|future_deck_order|privateRngState|private_rng_state)'
if git grep -nEI "$private_rng_pattern" -- apps/mobile/lib 2>/dev/null; then
  echo "Private RNG/deck state identifier leaked into mobile runtime source." >&2
  status=1
fi

if (( status != 0 )); then
  exit "$status"
fi

echo "Security artifact scan: PASS"
