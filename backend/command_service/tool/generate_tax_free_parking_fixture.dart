import 'dart:convert';
import 'dart:io';

import '../test/support/synthetic_tax_free_parking_plans.dart';

void main() {
  const encoder = JsonEncoder.withIndent('  ');
  File('test/fixtures/tax_free_parking_plans.json').writeAsStringSync(
    '${encoder.convert(syntheticTaxFreeParkingFixtureJson())}\n',
  );
}
