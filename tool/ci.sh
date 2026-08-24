#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
flutter pub get --enforce-lockfile

dart format apps/mobile/lib/ui/auction/auction_sheet.dart apps/mobile/test/auction_sheet_test.dart
git diff -- apps/mobile/lib/ui/auction/auction_sheet.dart apps/mobile/test/auction_sheet_test.dart
exit 1
