#!/usr/bin/env bash
set -euo pipefail

python3 -B tool/preflight.py --format-only
dart run tool/check_spec_registry.dart

# Tooling tests need no Atlassian call or credential; formatter fixtures use the pinned SDK.
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tool/test -p '*_test.py'

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
(
  cd backend/command_service
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
