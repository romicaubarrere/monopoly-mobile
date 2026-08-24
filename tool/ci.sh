#!/usr/bin/env bash
set -euo pipefail

flutter pub get --enforce-lockfile
dart format apps/mobile/lib/ui/property/property_management_surface.dart apps/mobile/test/property_management_surface_test.dart
echo '__FORMAT_DIFF_BEGIN__'
git diff -- apps/mobile/lib/ui/property/property_management_surface.dart apps/mobile/test/property_management_surface_test.dart
echo '__FORMAT_DIFF_END__'
exit 1
