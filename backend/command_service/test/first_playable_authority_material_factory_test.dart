import 'dart:convert';

import 'package:board_command_service/command_service.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  final key = List<int>.generate(32, (index) => index + 1);
  final factory = FirstPlayableAuthorityMaterialFactory(
    key: key,
    roomCodeTtl: const Duration(minutes: 10),
  );

  test(
    'Create material is stable across instances and never embeds the key',
    () async {
      final command = _roomCommand(
        'cmd-create-stable',
        RoomCommandType.createRoom,
      );
      final first = await factory.roomEntry(
        command,
        DateTime.parse('2026-08-26T20:00:00Z'),
      );
      final second = await FirstPlayableAuthorityMaterialFactory(
        key: List<int>.of(key),
        roomCodeTtl: const Duration(minutes: 10),
      ).roomEntry(command, DateTime.parse('2026-08-26T20:05:00Z'));

      expect(first.roomCode, second.roomCode);
      expect(first.codeHash, second.codeHash);
      expect(first.roomId, second.roomId);
      expect(first.playerId, second.playerId);
      expect(first.roomCode, matches(RegExp(r'^[A-Z0-9]{6}$')));
      expect(
        first.codeHash,
        sha256.convert(utf8.encode(first.roomCode)).toString(),
      );
      expect(first.expiresAt, DateTime.parse('2026-08-26T20:10:00Z'));
      expect(second.expiresAt, DateTime.parse('2026-08-26T20:15:00Z'));
      expect(first.roomId, isNot(contains(key.join())));
    },
  );

  test(
    'Join hashes client code and derives a stable authority player id',
    () async {
      final command = _roomCommand(
        'cmd-join-stable',
        RoomCommandType.joinRoom,
        roomCode: 'ABC123',
      );
      final first = await factory.roomEntry(command, DateTime.utc(2026));
      final second = await factory.roomEntry(command, DateTime.utc(2027));

      expect(first.kind, FirstPlayableRoomEntryKind.join);
      expect(first.roomCode, 'ABC123');
      expect(first.codeHash, sha256.convert(utf8.encode('ABC123')).toString());
      expect(first.playerId, second.playerId);
      expect(first.roomId, isNull);
      expect(first.expiresAt, isNull);
    },
  );

  test(
    'Start material is stable and domain-separated from room entry',
    () async {
      final command = _roomCommand(
        'cmd-start-stable',
        RoomCommandType.startGame,
        roomId: 'room-1',
      );
      final first = await factory.startGame(command);
      final second = await factory.startGame(command);

      expect(first.gameId, second.gameId);
      expect(first.seed, second.seed);
      expect(first.seed, hasLength(32));
      expect(first.gameId, matches(RegExp(r'^game-[a-f0-9]{32}$')));
      expect(first.gameId, isNot(contains(first.seed.first.toString())));
    },
  );

  test(
    'Factory rejects weak configuration and command-family misuse',
    () async {
      expect(
        () => FirstPlayableAuthorityMaterialFactory(
          key: List<int>.filled(31, 1),
          roomCodeTtl: const Duration(minutes: 10),
        ),
        throwsA(isA<FirstPlayableAuthorityExecutorViolation>()),
      );
      expect(
        () => FirstPlayableAuthorityMaterialFactory(
          key: key,
          roomCodeTtl: Duration.zero,
        ),
        throwsA(isA<FirstPlayableAuthorityExecutorViolation>()),
      );
      final ready = _roomCommand(
        'cmd-ready',
        RoomCommandType.setReady,
        roomId: 'room-1',
      );
      await expectLater(
        factory.roomEntry(ready, DateTime.utc(2026)),
        throwsA(isA<FirstPlayableAuthorityExecutorViolation>()),
      );
      await expectLater(
        factory.startGame(ready),
        throwsA(isA<FirstPlayableAuthorityExecutorViolation>()),
      );
    },
  );
}

RoomCommand _roomCommand(
  String commandId,
  RoomCommandType type, {
  String roomCode = 'ABC123',
  String roomId = 'room-1',
}) => RoomCommand(
  commandId: commandId,
  schemaVersion: 1,
  expectedRoomVersion:
      type == RoomCommandType.createRoom || type == RoomCommandType.joinRoom
      ? null
      : 1,
  clientInstanceId: 'client-material-test',
  type: type,
  payload: switch (type) {
    RoomCommandType.createRoom => const <String, Object?>{
      'presetDraft': <String, Object?>{'presetId': 'express'},
    },
    RoomCommandType.joinRoom => <String, Object?>{'roomCode': roomCode},
    RoomCommandType.setReady => <String, Object?>{
      'roomId': roomId,
      'ready': true,
    },
    RoomCommandType.startGame ||
    RoomCommandType.leaveRoom => <String, Object?>{'roomId': roomId},
    RoomCommandType.setPreset => <String, Object?>{
      'roomId': roomId,
      'presetDraft': const <String, Object?>{'presetId': 'express'},
    },
  },
);
