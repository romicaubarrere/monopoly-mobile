#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
flutter pub get --enforce-lockfile

dart format apps/mobile/lib/ui/trade/trade_surfaces.dart apps/mobile/test/trade_surfaces_test.dart
git diff -- apps/mobile/lib/ui/trade/trade_surfaces.dart apps/mobile/test/trade_surfaces_test.dart
exit 1
