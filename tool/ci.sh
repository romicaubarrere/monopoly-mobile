#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
flutter pub get --enforce-lockfile

# TEMPORARY read-only formatter probe for PR #60. Remove before acceptance.
dart format packages/game_core/lib/src/deadline_timeout.dart
if ! git diff --quiet -- packages/game_core/lib/src/deadline_timeout.dart; then
  echo '--- canonical Dart formatter diff ---'
  git diff -- packages/game_core/lib/src/deadline_timeout.dart
  exit 1
fi

dart format --output=none --set-exit-if-changed apps packages backend
dart run tool/check_spec_registry.dart

dart analyze packages/game_core packages/game_contracts packages/backend_api backend/command_service
(
  cd apps/mobile
  flutter analyze
)

(
  cd packages/game_core
  dart test
)
(
  cd packages/game_contracts
  dart test
)
(
  cd packages/backend_api
  dart test
)
dart run backend/command_service/tool/observability_smoke.dart
dart run backend/command_service/tool/ingress_observability_smoke.dart
dart run backend/command_service/tool/identity_security_smoke.dart
dart run backend/command_service/tool/secure_token_cert_cache_smoke.dart
(
  cd apps/mobile
  flutter test
)

./tool/check_architecture.sh
