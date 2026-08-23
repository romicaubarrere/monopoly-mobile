#!/usr/bin/env bash
set -euo pipefail

for package in packages/game_core packages/game_contracts; do
  if grep -RInE "package:(flutter|firebase_|cloud_firestore|http|dart_jsonwebtoken|flutter_riverpod)/" "$package/lib" "$package/test"; then
    echo "Forbidden platform/infrastructure dependency found in $package" >&2
    exit 1
  fi
done

if grep -RIn "Monopoly" packages backend apps/mobile/lib --exclude-dir=.dart_tool; then
  echo "Development brand leaked into rebrandable code boundary" >&2
  exit 1
fi

echo "Architecture boundaries: PASS"
