import 'package:board_backend_api/backend_api.dart';
import 'package:test/test.dart';

void main() {
  test('locator store persists only canonical public identifiers', () async {
    String? durableValue;
    final store = JsonFirstPlayableSessionLocatorStore(
      read: () async => durableValue,
      write: (value) async => durableValue = value,
    );

    await store.save(
      FirstPlayableSessionLocator(roomId: 'room-1', gameId: 'game-1'),
    );
    final restored = await store.load();

    expect(
      durableValue,
      '{"schemaVersion":1,"roomId":"room-1","gameId":"game-1"}',
    );
    expect(restored!.roomId, 'room-1');
    expect(restored.gameId, 'game-1');
    expect(durableValue, isNot(contains('actor')));
    expect(durableValue, isNot(contains('uid')));
  });

  test('locator store rejects extra or non-canonical material', () async {
    final store = JsonFirstPlayableSessionLocatorStore(
      read: () async =>
          '{"schemaVersion":1,"roomId":"room-1","memberUid":"uid-1"}',
      write: (_) async {},
    );

    expect(
      store.load(),
      throwsA(
        isA<ClientAuthorityContractViolation>().having(
          (error) => error.code,
          'code',
          'sessionLocatorCorrupt',
        ),
      ),
    );
  });
}
