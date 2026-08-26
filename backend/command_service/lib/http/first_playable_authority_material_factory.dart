import 'dart:convert';
import 'dart:typed_data';

import 'package:board_game_contracts/game_contracts.dart';
import 'package:crypto/crypto.dart';

import 'first_playable_authority_executor.dart';

/// Keyed, stateless material derivation for the First Playable authority.
///
/// This key is infrastructure-private and independent from every game RNG
/// seed. Stable derivation lets different instances reproduce command material
/// after a lost ACK without persisting plaintext room codes or RNG seeds.
final class FirstPlayableAuthorityMaterialFactory {
  factory FirstPlayableAuthorityMaterialFactory.fromEnvironment({
    required Map<String, String> environment,
    required Duration roomCodeTtl,
  }) {
    final encodedKey = environment[materialKeyEnvironmentVariable];
    if (encodedKey == null || encodedKey.isEmpty) {
      throw const FirstPlayableAuthorityExecutorViolation('materialKeyMissing');
    }
    if (encodedKey.trim() != encodedKey) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'materialKeyMalformed',
      );
    }
    late final List<int> key;
    try {
      key = base64Decode(encodedKey);
    } on FormatException {
      throw const FirstPlayableAuthorityExecutorViolation(
        'materialKeyMalformed',
      );
    }
    if (base64Encode(key) != encodedKey) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'materialKeyMalformed',
      );
    }
    return FirstPlayableAuthorityMaterialFactory(
      key: key,
      roomCodeTtl: roomCodeTtl,
    );
  }

  FirstPlayableAuthorityMaterialFactory({
    required List<int> key,
    required this.roomCodeTtl,
  }) : _key = Uint8List.fromList(key) {
    if (_key.length < 32) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'materialKeyTooShort',
      );
    }
    if (roomCodeTtl <= Duration.zero) {
      throw const FirstPlayableAuthorityExecutorViolation('invalidRoomCodeTtl');
    }
  }

  static const String _roomCodeAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// Infrastructure-only secret. Flutter and persisted documents must never
  /// receive this value.
  static const String materialKeyEnvironmentVariable =
      'FIRST_PLAYABLE_AUTHORITY_HMAC_KEY_BASE64';

  final Uint8List _key;
  final Duration roomCodeTtl;

  Future<FirstPlayableStartMaterial> startGame(RoomCommand command) async {
    if (command.type != RoomCommandType.startGame) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'startMaterialCommandMismatch',
      );
    }
    final gameIdDigest = _derive('start-game-id-v1', command.commandId);
    final seed = _derive('start-game-seed-v1', command.commandId);
    return FirstPlayableStartMaterial(
      gameId: 'game-${_hex(gameIdDigest).substring(0, 32)}',
      seed: seed,
    );
  }

  Future<FirstPlayableRoomEntryMaterial> roomEntry(
    RoomCommand command,
    DateTime requestReceivedAt,
  ) async {
    final receivedAt = requestReceivedAt.toUtc();
    switch (command.type) {
      case RoomCommandType.createRoom:
        final roomCode = _deriveRoomCode(command.commandId);
        return FirstPlayableRoomEntryMaterial(
          kind: FirstPlayableRoomEntryKind.create,
          roomCode: roomCode,
          codeHash: sha256.convert(utf8.encode(roomCode)).toString(),
          playerId:
              'player-${_hex(_derive('create-player-id-v1', command.commandId)).substring(0, 32)}',
          roomId:
              'room-${_hex(_derive('create-room-id-v1', command.commandId)).substring(0, 32)}',
          expiresAt: receivedAt.add(roomCodeTtl),
        );
      case RoomCommandType.joinRoom:
        final roomCode = command.payload['roomCode']! as String;
        return FirstPlayableRoomEntryMaterial(
          kind: FirstPlayableRoomEntryKind.join,
          roomCode: roomCode,
          codeHash: sha256.convert(utf8.encode(roomCode)).toString(),
          playerId:
              'player-${_hex(_derive('join-player-id-v1', command.commandId)).substring(0, 32)}',
        );
      case RoomCommandType.leaveRoom:
      case RoomCommandType.setReady:
      case RoomCommandType.setPreset:
      case RoomCommandType.startGame:
        throw const FirstPlayableAuthorityExecutorViolation(
          'roomEntryMaterialCommandMismatch',
        );
    }
  }

  Uint8List _derive(String domain, String commandId, [int counter = 0]) =>
      Uint8List.fromList(
        Hmac(
          sha256,
          _key,
        ).convert(utf8.encode('$domain\u0000$commandId\u0000$counter')).bytes,
      );

  String _deriveRoomCode(String commandId) {
    final output = StringBuffer();
    var counter = 0;
    while (output.length < 6) {
      for (final byte in _derive('create-room-code-v1', commandId, counter++)) {
        // 252 is the greatest multiple of 36 below 256. Rejection avoids
        // modulo bias while keeping derivation deterministic.
        if (byte >= 252) continue;
        output.write(_roomCodeAlphabet[byte % _roomCodeAlphabet.length]);
        if (output.length == 6) break;
      }
    }
    return output.toString();
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
