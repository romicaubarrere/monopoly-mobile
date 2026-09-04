import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('one device port keeps pending command and locator isolated', () async {
    final values = <String, String>{};
    final storage = FirstPlayableAuthorityDeviceStorage(
      read: (key) async => values[key],
      write: (key, value) async {
        if (value == null) {
          values.remove(key);
        } else {
          values[key] = value;
        }
      },
    );
    final request = AuthorityCommandRequest.room(
      RoomCommand(
        commandId: 'command-1',
        schemaVersion: 1,
        clientInstanceId: 'client-1',
        type: RoomCommandType.createRoom,
        payload: const <String, Object?>{
          'presetDraft': <String, Object?>{'presetId': 'synthetic-vp0'},
        },
      ),
    );

    await storage.pendingCommands.save(request);
    await storage.sessionLocator.save(
      FirstPlayableSessionLocator(roomId: 'room-1', gameId: 'game-1'),
    );

    expect(values.keys, {
      'la_vuelta.authority.v1.pending-command',
      'la_vuelta.authority.v1.session-locator',
    });
    expect(
      (await storage.pendingCommands.load())!.commandId,
      request.commandId,
    );
    expect((await storage.sessionLocator.load())!.gameId, 'game-1');
    expect(values.values.join(), isNot(contains('uid-')));

    await storage.pendingCommands.clear(request.commandId);
    expect(
      values.containsKey('la_vuelta.authority.v1.pending-command'),
      isFalse,
    );
    expect(
      values.containsKey('la_vuelta.authority.v1.session-locator'),
      isTrue,
    );
  });

  test('storage namespace is strict and versionable', () {
    FirstPlayableAuthorityDeviceStorage build(String namespace) =>
        FirstPlayableAuthorityDeviceStorage(
          namespace: namespace,
          read: (_) async => null,
          write: (_, _) async {},
        );

    expect(() => build('la_vuelta.authority.v2'), returnsNormally);
    for (final invalid in <String>[
      '',
      'LaVuelta',
      ' la_vuelta',
      'la/vuelta',
      '1la_vuelta',
    ]) {
      expect(
        () => build(invalid),
        throwsA(
          isA<ClientAuthorityContractViolation>().having(
            (error) => error.code,
            'code',
            'invalidAuthorityStorageNamespace',
          ),
        ),
      );
    }
  });
}
