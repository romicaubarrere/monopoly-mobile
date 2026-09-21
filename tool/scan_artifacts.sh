#!/usr/bin/env bash
set -euo pipefail

status=0

# Keep source contents, filenames and Git diagnostics out of CI output.
# A failed enumeration is not an empty repository.
if tracked_files="$(git ls-files 2>/dev/null)"; then
  :
else
  echo "Security artifact scan could not enumerate tracked files." >&2
  exit 1
fi

forbidden_files='(^|/)(\.env($|\.)|serviceAccount[^/]*\.json$|google-services\.json$|GoogleService-Info\.plist$|[^/]+\.(p8|p12)$)'
if grep -E -e "$forbidden_files" <<< "$tracked_files" >/dev/null 2>&1; then
  echo "Forbidden credential/environment artifact is tracked." >&2
  status=1
else
  scan_status=$?
  if (( scan_status != 1 )); then
    echo "Security artifact scan could not inspect tracked filenames." >&2
    status=1
  fi
fi

scan_content() {
  local pattern="$1"
  local message="$2"
  local scan_error scan_status
  shift 2

  # -e is essential for patterns beginning with '-'. Do not use -q: finish
  # reading the selected files. Git can report unreadable files on stderr
  # while returning 1, so only 1 with empty stderr is a clean no-match.
  # Redirection order captures stderr privately and discards matched content.
  if scan_error="$(git grep -EI -e "$pattern" -- "$@" 2>&1 >/dev/null)"; then
    echo "$message" >&2
    status=1
  else
    scan_status=$?
    if (( scan_status != 1 )) || [[ -n "$scan_error" ]]; then
      echo "Security artifact scan could not inspect tracked content." >&2
      status=1
    fi
  fi
}

secret_pattern='-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|AIza[0-9A-Za-z_-]{35}|ya29\.[0-9A-Za-z._-]+|gh[pousr]_[0-9A-Za-z]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|"private_key"[[:space:]]*:'
scan_content "$secret_pattern" \
  "Potential credential/private key material found in executable repository surfaces." \
  apps packages backend .github ':!**/*.md' ':!**/test/**' ':!**/test_*'

private_rng_pattern='(rngSeed|rng_seed|futureDeckOrder|future_deck_order|privateRngState|private_rng_state)'
scan_content "$private_rng_pattern" \
  "Private RNG/deck state identifier leaked into mobile runtime source." \
  apps/mobile/lib

if (( status != 0 )); then
  exit "$status"
fi

echo "Security artifact scan: PASS"
