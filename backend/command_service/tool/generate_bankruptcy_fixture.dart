import 'dart:convert';
import 'dart:io';

import '../test/support/synthetic_bankruptcy_plans.dart';

void main() {
  const encoder = JsonEncoder.withIndent('  ');
  File(
    'test/fixtures/bankruptcy_plans.json',
  ).writeAsStringSync('${encoder.convert(syntheticBankruptcyFixtureJson())}\n');
}
