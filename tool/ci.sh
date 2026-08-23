#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
flutter pub get

# Temporary bootstrap evidence: print the resolver-produced lockfile so the
# exact Flutter/Dart resolution can be committed in this PR.
cat pubspec.lock

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
  cd apps/mobile
  flutter test
)

./tool/check_architecture.sh
