#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
flutter pub get --enforce-lockfile

dart format apps packages backend

echo '--- semantic_fingerprint.dart ---'
cat packages/backend_api/lib/src/semantic_fingerprint.dart
echo '--- idempotency_guard_test.dart ---'
cat packages/backend_api/test/idempotency_guard_test.dart
echo '--- semantic_fingerprint_test.dart ---'
cat packages/backend_api/test/semantic_fingerprint_test.dart
exit 1
