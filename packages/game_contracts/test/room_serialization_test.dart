import 'dart:convert';

import 'package:board_game_contracts/game_contracts.dart';
import 'package:test/test.dart';

void main() {
  const commandGoldens = <String, String>{
    'CreateRoom': '{"clientInstanceId":"client","commandId":"cmd","payload":{"presetDraft":{"presetId":"express"}},"schemaVersion":1,"type":"CreateRoom"}',
    'JoinRoom': '{"clientInstanceId":"client","commandId":"cmd","payload":{"roomCode":"ABC123"},"schemaVersion":1,"type":"JoinRoom"}',
    'LeaveRoom': '{"clientInstanceId":"client","commandId":"cmd","expectedRoomVersion":3,"payload":{"roomId":"room"},"schemaVersion":1,"type":"LeaveRoom"}',
    'SetReady': '{"clientInstanceId":"client","commandId":"cmd","expectedRoomVersion":3,"payload":{"ready":true,"roomId":"room"},"schemaVersion":1,"type":"SetReady"}',
    'SetPreset': '{"clientInstanceId":"client","commandId":"cmd","expectedRoomVersion":3,"payload":{"presetDraft":{"presetId":"classic"},"roomId":"room"},"schemaVersion":1,"type":"SetPreset"}',
    'StartGame': '{"clientInstanceId":"client","commandId":"cmd","expectedRoomVersion":3,"payload":{"roomId":"room"},"schemaVersion":1,"sentAt":"2026-08-25T00:00:00.000Z","type":"StartGame"}',
  };
  for (final fixture in commandGoldens.entries) {
    test('${fixture.key} generated codec preserves the canonical golden', () {
      final json = jsonDecode(fixture.value) as Map<String, Object?>;
      final command = RoomCommand.fromJson(json);
      expect(command.toCanonicalJson(), fixture.value);
      expect(
        RoomCommand.fromJson(command.toJson()).toCanonicalJson(),
        fixture.value,
      );
      expect(command.toJson(), json);
      expect(command.type.wireValue, fixture.key);
    });
  }

  const resultGoldens = <String>[
    '{"commandId":"cmd","gameId":"game","roomSnapshot":{"roomId":"room","status":"active"},"roomVersionAfter":4,"roomVersionBefore":3,"serverProcessedAt":"2026-08-25T00:00:00.000Z","status":"accepted"}',
    '{"commandId":"cmd","errorCode":"notAMember","roomVersionAfter":3,"roomVersionBefore":3,"serverProcessedAt":"2026-08-25T00:00:00.000Z","status":"rejected"}',
    '{"commandId":"cmd","roomVersionAfter":4,"roomVersionBefore":3,"serverProcessedAt":"2026-08-25T00:00:00.000Z","status":"duplicate"}',
  ];
  for (var index = 0; index < resultGoldens.length; index += 1) {
    test('result $index generated codec preserves the canonical golden', () {
      final golden = resultGoldens[index];
      final json = jsonDecode(golden) as Map<String, Object?>;
      final result = RoomCommandResult.fromJson(json);
      expect(result.toJson(), json);
      expect(result.toCanonicalJson(), golden);
      expect(
        RoomCommandResult.fromJson(result.toJson()).toCanonicalJson(),
        golden,
      );
    });
  }

  Map<String, Object?> start() =>
      jsonDecode(commandGoldens['StartGame']!) as Map<String, Object?>;
  Map<String, Object?> result() =>
      jsonDecode(resultGoldens.first) as Map<String, Object?>;

  for (final version in [0, 2, -1, 999]) {
    test('unknown schemaVersion $version fails closed', () {
      expect(
        () => RoomCommand.fromJson(start()..['schemaVersion'] = version),
        throwsA(isA<RoomContractViolation>()),
      );
    });
  }
  for (final field in ['schemaVersion', 'expectedRoomVersion']) {
    for (final value in <Object>[1.5, 1.0, '1', true]) {
      test('$field does not coerce ${value.runtimeType} into an integer', () {
        expect(
          () => RoomCommand.fromJson(start()..[field] = value),
          throwsA(isA<RoomContractViolation>()),
        );
      });
    }
  }
  for (final field in ['roomVersionBefore', 'roomVersionAfter']) {
    test('$field does not truncate a fractional result version', () {
      expect(
        () => RoomCommandResult.fromJson(result()..[field] = 3.5),
        throwsA(isA<RoomContractViolation>()),
      );
    });
  }
  test('large integer versions survive generated decoding exactly', () {
    const version = 4611686018427387904;
    final decoded = RoomCommand.fromJson(
      start()..['expectedRoomVersion'] = version,
    );
    expect(decoded.expectedRoomVersion, version);
    expect(decoded.toJson()['expectedRoomVersion'], version);
  });
  test('version one rejects unknown envelope fields', () {
    expect(
      () => RoomCommand.fromJson(start()..['actorUid'] = 'untrusted'),
      throwsA(isA<Exception>()),
    );
    expect(
      () => RoomCommandResult.fromJson(result()..['unexpected'] = true),
      throwsA(isA<Exception>()),
    );
  });
  for (final field in [
    'commandId',
    'clientInstanceId',
    'schemaVersion',
    'type',
    'payload',
  ]) {
    test('missing required $field fails closed', () {
      expect(
        () => RoomCommand.fromJson(start()..remove(field)),
        throwsA(isA<Exception>()),
      );
    });
  }
  test('wire enum names and payload validation remain strict', () {
    expect(
      () => RoomCommand.fromJson(start()..['type'] = 'startGame'),
      throwsA(isA<Exception>()),
    );
    expect(
      () => RoomCommand.fromJson(
        start()..['payload'] = {'roomId': 'room', 'extra': true},
      ),
      throwsA(isA<RoomContractViolation>()),
    );
    expect(
      () => RoomCommand.fromJson(
        start()..['payload'] = {'roomId': 'room', 'cash': 1.5},
      ),
      throwsA(isA<RoomContractViolation>()),
    );
  });
  test(
    'generated timestamps normalize UTC without changing the wire policy',
    () {
      final command = RoomCommand.fromJson(
        start()..['sentAt'] = '2026-08-24T21:00:00-03:00',
      );
      expect(command.toJson()['sentAt'], '2026-08-25T00:00:00.000Z');
      final decoded = RoomCommandResult.fromJson(
        result()..['serverProcessedAt'] = '2026-08-24T21:00:00-03:00',
      );
      expect(decoded.toJson()['serverProcessedAt'], '2026-08-25T00:00:00.000Z');
      expect(
        () => RoomCommand.fromJson(start()..['sentAt'] = 42),
        throwsA(isA<RoomContractViolation>()),
      );
    },
  );
  test('result decoding still enforces accepted-version increments', () {
    expect(
      () => RoomCommandResult.fromJson(result()..['roomVersionAfter'] = 5),
      throwsA(isA<RoomContractViolation>()),
    );
  });
}
