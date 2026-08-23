import 'dart:collection';
import 'dart:convert';

import 'package:board_game_contracts/game_contracts.dart';
import 'package:crypto/crypto.dart';

/// Canonical semantic command fingerprint defined by DEC-052.
///
/// The caller supplies semantic command material only. Transport metadata,
/// authentication tokens, authenticated UID, commandId, sentAt and
/// clientInstanceId do not belong in this object.
abstract final class SemanticFingerprintV1 {
  static const int version = ProtocolFoundation.inputHashVersion;

  static String canonicalJson(Object? semanticMaterial) {
    final Object? canonical = _canonicalize(semanticMaterial);
    return jsonEncode(canonical);
  }

  static String sha256Hex(Object? semanticMaterial) {
    final String canonical = canonicalJson(semanticMaterial);
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static Object? _canonicalize(Object? value) {
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }

    if (value is num) {
      throw ArgumentError.value(
        value,
        'semanticMaterial',
        'Fingerprint v1 accepts domain integers, never floating-point values.',
      );
    }

    if (value is List<Object?>) {
      return value.map<Object?>(_canonicalize).toList(growable: false);
    }

    if (value is Map) {
      final SplayTreeMap<String, Object?> sorted = SplayTreeMap<String, Object?>();
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        final Object? key = entry.key;
        if (key is! String) {
          throw ArgumentError.value(
            key,
            'semanticMaterial',
            'Fingerprint v1 object keys must be strings.',
          );
        }
        sorted[key] = _canonicalize(entry.value);
      }
      return sorted;
    }

    throw ArgumentError.value(
      value,
      'semanticMaterial',
      'Unsupported fingerprint v1 value type ${value.runtimeType}.',
    );
  }
}
