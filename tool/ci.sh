#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
flutter pub get

dart format --output=none --set-exit-if-changed apps packages backend
flutter analyze

dart test packages/game_core
dart test packages/game_contracts
flutter test apps/mobile

./tool/check_architecture.sh
