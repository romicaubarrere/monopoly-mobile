#!/usr/bin/env bash
set -euo pipefail

flutter --version
dart --version
flutter pub get --enforce-lockfile

dart format apps/mobile/lib/analytics/product_analytics.dart apps/mobile/test/product_analytics_test.dart
git diff -- apps/mobile/lib/analytics/product_analytics.dart apps/mobile/test/product_analytics_test.dart
exit 1
