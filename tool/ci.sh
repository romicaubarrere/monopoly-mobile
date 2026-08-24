#!/usr/bin/env bash
set -euo pipefail

echo '__PROPERTY_MANAGEMENT_SOURCE_BEGIN__'
dart format --output=show apps/mobile/lib/ui/property/property_management_surface.dart
echo '__PROPERTY_MANAGEMENT_SOURCE_END__'
echo '__PROPERTY_MANAGEMENT_TEST_BEGIN__'
dart format --output=show apps/mobile/test/property_management_surface_test.dart
echo '__PROPERTY_MANAGEMENT_TEST_END__'
exit 1
