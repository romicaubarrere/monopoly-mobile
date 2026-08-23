#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
flutter pub get --enforce-lockfile

echo 'FORMAT_PROBE_PROPERTY_BEGIN'
dart format --output=show apps/mobile/lib/ui/property/property_offer_sheet.dart
echo 'FORMAT_PROBE_PROPERTY_END'
echo 'FORMAT_PROBE_PROPERTY_TEST_BEGIN'
dart format --output=show apps/mobile/test/property_offer_sheet_test.dart
echo 'FORMAT_PROBE_PROPERTY_TEST_END'

dart format --output=none --set-exit-if-changed apps packages backend

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
  cd apps/mobile
  flutter test
)

./tool/check_architecture.sh
