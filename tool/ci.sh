#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
flutter pub get --enforce-lockfile

echo 'FORMAT_PROBE_BOARD_BEGIN'
dart format --output=show apps/mobile/lib/ui/game_board/board_turn_surface.dart
echo 'FORMAT_PROBE_BOARD_END'
echo 'FORMAT_PROBE_TEST_BEGIN'
dart format --output=show apps/mobile/test/board_turn_surface_test.dart
echo 'FORMAT_PROBE_TEST_END'

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
