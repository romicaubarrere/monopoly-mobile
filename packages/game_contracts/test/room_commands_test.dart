import 'package:board_game_contracts/game_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('StartGame is versioned, actor-free, and byte-stable', () {
    final command = RoomCommand(
      commandId: 'cmd-start-1',
      schemaVersion: 1,
      expectedRoomVersion: 7,
      clientInstanceId: 'client-a',
      type: RoomCommandType.startGame,
      payload: const <String, Object?>{'roomId': 'room-a'},
      sentAt: DateTime.parse('2026-08-24T21:00:00-03:00'),
    );

    expect(
      command.toCanonicalJson(),
      '{"clientInstanceId":"client-a","commandId":"cmd-start-1",'
      '"expectedRoomVersion":7,"payload":{"roomId":"room-a"},'
      '"schemaVersion":1,"sentAt":"2026-08-25T00:00:00.000Z",'
      '"type":"StartGame"}',
    );
    expect(command.toCanonicalJson(), isNot(contains('actorUid')));
  });

  test('SetReady requires version, exact payload, and boolean ready', () {
    expect(
      () => RoomCommand(
        commandId: 'cmd-ready',
        schemaVersion: 1,
        clientInstanceId: 'client-a',
        type: RoomCommandType.setReady,
        payload: const <String, Object?>{'roomId': 'room-a', 'ready': true},
      ),
      throwsA(isA<RoomContractViolation>()),
    );
    expect(
      () => RoomCommand(
        commandId: 'cmd-ready',
        schemaVersion: 1,
        expectedRoomVersion: 0,
        clientInstanceId: 'client-a',
        type: RoomCommandType.setReady,
        payload: const <String, Object?>{'roomId': 'room-a', 'ready': 1},
      ),
      throwsA(isA<RoomContractViolation>()),
    );
  });

  test('accepted result advances roomVersion exactly once', () {
    final result = RoomCommandResult(
      commandId: 'cmd-start-1',
      status: RoomCommandStatus.accepted,
      roomVersionBefore: 7,
      roomVersionAfter: 8,
      gameId: 'game-a',
      roomSnapshot: const <String, Object?>{
        'roomId': 'room-a',
        'status': 'active',
      },
      serverProcessedAt: DateTime.parse('2026-08-25T00:00:01Z'),
    );

    expect(result.gameId, 'game-a');
    expect(
      () => RoomCommandResult(
        commandId: 'cmd-start-2',
        status: RoomCommandStatus.accepted,
        roomVersionBefore: 7,
        roomVersionAfter: 9,
        serverProcessedAt: DateTime.now(),
      ),
      throwsA(isA<RoomContractViolation>()),
    );
  });
}
