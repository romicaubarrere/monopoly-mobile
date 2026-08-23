import 'package:board_backend_api/backend_api.dart';
import 'package:test/test.dart';

void main() {
  group('DEC-052 fingerprint v1', () {
    test('TV-35 BuyProperty reproduces canonical bytes and SHA-256', () {
      final Map<String, Object?> material = <String, Object?>{
        'v': 1,
        'family': 'game',
        'type': 'BuyProperty',
        'target': 'game-g1',
        'expectedVersion': 42,
        'actorPlayerId': 'p1',
        'payload': <String, Object?>{'propertyId': 'prop-17'},
      };

      expect(
        SemanticFingerprintV1.canonicalJson(material),
        '{"actorPlayerId":"p1","expectedVersion":42,"family":"game","payload":{"propertyId":"prop-17"},"target":"game-g1","type":"BuyProperty","v":1}',
      );
      expect(
        SemanticFingerprintV1.sha256Hex(material),
        '78d0fbe664826ccdfe13783517be5f7c01acb5696c601fe1e6f1f6868be513a4',
      );
    });

    test('TV-36 recursive map insertion order is irrelevant', () {
      final Map<String, Object?> first = _tradeMaterial(reverse: false);
      final Map<String, Object?> second = _tradeMaterial(reverse: true);

      expect(
        SemanticFingerprintV1.canonicalJson(first),
        SemanticFingerprintV1.canonicalJson(second),
      );
      expect(
        SemanticFingerprintV1.sha256Hex(first),
        '8033df65c688e43a61827a9cdf98c2ec0093855b4e482482b3c2da3d175e184e',
      );
      expect(
        SemanticFingerprintV1.sha256Hex(second),
        '8033df65c688e43a61827a9cdf98c2ec0093855b4e482482b3c2da3d175e184e',
      );
    });

    test('TV-37 expectedVersion change produces collision hash', () {
      final Map<String, Object?> material = _buyProperty(
        version: 43,
        propertyId: 'prop-17',
      );
      expect(
        SemanticFingerprintV1.sha256Hex(material),
        '3f01096ae2ab2bb7da08d63123bacaa51285c03f58340661821e27855cc6e9ac',
      );
    });

    test('TV-38 payload change produces collision hash', () {
      final Map<String, Object?> material = _buyProperty(
        version: 42,
        propertyId: 'prop-18',
      );
      expect(
        SemanticFingerprintV1.sha256Hex(material),
        '10d2aef3d71e10c40e5ad4ade21c3407f891b5d6c74529b8067d83f34c413ea2',
      );
    });

    test('fingerprint v1 rejects floats and non-string map keys', () {
      expect(
        () => SemanticFingerprintV1.sha256Hex(<String, Object?>{'cash': 1.0}),
        throwsArgumentError,
      );
      expect(
        () => SemanticFingerprintV1.sha256Hex(<Object?, Object?>{1: 'bad-key'}),
        throwsArgumentError,
      );
    });
  });
}

Map<String, Object?> _buyProperty({
  required int version,
  required String propertyId,
}) {
  return <String, Object?>{
    'v': 1,
    'family': 'game',
    'type': 'BuyProperty',
    'target': 'game-g1',
    'expectedVersion': version,
    'actorPlayerId': 'p1',
    'payload': <String, Object?>{'propertyId': propertyId},
  };
}

Map<String, Object?> _tradeMaterial({required bool reverse}) {
  final Map<String, Object?> offer = reverse
      ? <String, Object?>{
          'propertyIds': <Object?>['prop-03', 'prop-11'],
          'keepCardIds': <Object?>[],
          'cash': 200,
        }
      : <String, Object?>{
          'cash': 200,
          'keepCardIds': <Object?>[],
          'propertyIds': <Object?>['prop-03', 'prop-11'],
        };
  final Map<String, Object?> request = reverse
      ? <String, Object?>{
          'propertyIds': <Object?>['prop-22'],
          'keepCardIds': <Object?>['cucha-1'],
          'cash': 0,
        }
      : <String, Object?>{
          'cash': 0,
          'keepCardIds': <Object?>['cucha-1'],
          'propertyIds': <Object?>['prop-22'],
        };

  return reverse
      ? <String, Object?>{
          'payload': <String, Object?>{
            'request': request,
            'toPlayerId': 'p2',
            'offer': offer,
          },
          'actorPlayerId': 'p1',
          'expectedVersion': 91,
          'target': 'game-g1',
          'type': 'ProposeTrade',
          'family': 'game',
          'v': 1,
        }
      : <String, Object?>{
          'v': 1,
          'family': 'game',
          'type': 'ProposeTrade',
          'target': 'game-g1',
          'expectedVersion': 91,
          'actorPlayerId': 'p1',
          'payload': <String, Object?>{
            'offer': offer,
            'request': request,
            'toPlayerId': 'p2',
          },
        };
}
