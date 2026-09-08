import 'dart:convert';
import 'dart:io';

import '../test/support/public_snapshot_size_evidence.dart';

/// Prints deterministic metadata only, from committed synthetic fixtures.
/// Does not write files, contact a service or accept arbitrary input paths.
void main(List<String> arguments) {
  if (arguments.isNotEmpty) {
    stderr.writeln('Usage: dart run tool/report_public_snapshot_sizes.dart');
    exitCode = 64;
    return;
  }
  final fixtures = <String, Object?>{
    for (final name in publicSnapshotFixturePaths.keys)
      name: jsonDecode(
        File.fromUri(Platform.script.resolve('../test/fixtures/$name'))
            .readAsStringSync(),
      ),
  };
  stdout.writeln(
    const JsonEncoder.withIndent('  ')
        .convert(publicSnapshotSizeEvidence(fixtures)),
  );
}
