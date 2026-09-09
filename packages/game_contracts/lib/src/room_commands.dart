import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';

part 'room_commands.g.dart';

final class RoomContractViolation implements Exception {
  const RoomContractViolation(this.message);

  final String message;

  @override
  String toString() => 'RoomContractViolation: $message';
}

@JsonEnum(valueField: 'wireValue')
enum RoomCommandType {
  createRoom('CreateRoom'),
  joinRoom('JoinRoom'),
  leaveRoom('LeaveRoom'),
  setReady('SetReady'),
  setPreset('SetPreset'),
  startGame('StartGame');

  const RoomCommandType(this.wireValue);

  final String wireValue;
}

@JsonEnum(valueField: 'wireValue')
enum RoomCommandStatus {
  accepted('accepted'),
  rejected('rejected'),
  duplicate('duplicate');

  const RoomCommandStatus(this.wireValue);

  final String wireValue;
}

/// Pre-game command envelope. Authenticated identity is deliberately absent:
/// authority derives the actor UID from the verified token.
@JsonSerializable(disallowUnrecognizedKeys: true, includeIfNull: false)
final class RoomCommand {
  RoomCommand({
    required this.commandId,
    required this.schemaVersion,
    this.expectedRoomVersion,
    required this.clientInstanceId,
    required this.type,
    required Map<String, Object?> payload,
    DateTime? sentAt,
  }) : payload = _immutableJson(payload),
       sentAt = sentAt?.toUtc() {
    _identifier(commandId, 'commandId');
    _identifier(clientInstanceId, 'clientInstanceId');
    if (schemaVersion != 1) {
      throw RoomContractViolation('Unsupported schemaVersion: $schemaVersion');
    }
    if (expectedRoomVersion != null && expectedRoomVersion! < 0) {
      throw const RoomContractViolation(
        'expectedRoomVersion must be non-negative',
      );
    }
    final requiresVersion =
        type != RoomCommandType.createRoom && type != RoomCommandType.joinRoom;
    if (requiresVersion != (expectedRoomVersion != null)) {
      throw RoomContractViolation(
        '${type.wireValue} has invalid expectedRoomVersion presence',
      );
    }
    _validatePayload();
  }

  factory RoomCommand.fromJson(Map<String, Object?> json) {
    try {
      return _$RoomCommandFromJson(json);
    } on RoomContractViolation {
      rethrow;
    } on Object {
      throw const RoomContractViolation('Invalid RoomCommand JSON');
    }
  }

  @JsonKey(required: true)
  final String commandId;
  @JsonKey(required: true, fromJson: _requiredInteger)
  final int schemaVersion;
  @JsonKey(fromJson: _optionalInteger)
  final int? expectedRoomVersion;
  @JsonKey(required: true)
  final String clientInstanceId;
  @JsonKey(required: true)
  final RoomCommandType type;
  @JsonKey(required: true)
  final Map<String, Object?> payload;
  @JsonKey(fromJson: _optionalUtcDate)
  final DateTime? sentAt;

  void _validatePayload() {
    final expectedKeys = switch (type) {
      RoomCommandType.createRoom => <String>{'presetDraft'},
      RoomCommandType.joinRoom => <String>{'roomCode'},
      RoomCommandType.leaveRoom => <String>{'roomId'},
      RoomCommandType.setReady => <String>{'roomId', 'ready'},
      RoomCommandType.setPreset => <String>{'roomId', 'presetDraft'},
      RoomCommandType.startGame => <String>{'roomId'},
    };
    if (payload.keys.toSet().length != expectedKeys.length ||
        !payload.keys.toSet().containsAll(expectedKeys)) {
      throw RoomContractViolation(
        '${type.wireValue} payload must contain exactly ${expectedKeys.join(', ')}',
      );
    }
    switch (type) {
      case RoomCommandType.createRoom:
      case RoomCommandType.setPreset:
        if (payload['presetDraft'] is! Map<String, Object?>) {
          throw const RoomContractViolation('presetDraft must be an object');
        }
      case RoomCommandType.joinRoom:
        final code = payload['roomCode'];
        if (code is! String || !RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
          throw const RoomContractViolation(
            'roomCode must be six uppercase alphanumeric characters',
          );
        }
      case RoomCommandType.leaveRoom:
      case RoomCommandType.setReady:
      case RoomCommandType.startGame:
        final roomId = payload['roomId'];
        if (roomId is! String || roomId.isEmpty) {
          throw const RoomContractViolation('roomId must not be empty');
        }
        if (type == RoomCommandType.setReady && payload['ready'] is! bool) {
          throw const RoomContractViolation('ready must be boolean');
        }
    }
  }

  Map<String, Object?> toJson() => _$RoomCommandToJson(this);

  String toCanonicalJson() => _canonicalJson(toJson());
}

@JsonSerializable(disallowUnrecognizedKeys: true, includeIfNull: false)
final class RoomCommandResult {
  RoomCommandResult({
    required this.commandId,
    required this.status,
    this.roomVersionBefore,
    this.roomVersionAfter,
    this.errorCode,
    Map<String, Object?>? roomSnapshot,
    this.gameId,
    required DateTime serverProcessedAt,
  }) : roomSnapshot = roomSnapshot == null
           ? null
           : _immutableJson(roomSnapshot),
       serverProcessedAt = serverProcessedAt.toUtc() {
    _identifier(commandId, 'commandId');
    if (roomVersionBefore != null && roomVersionBefore! < 0 ||
        roomVersionAfter != null && roomVersionAfter! < 0) {
      throw const RoomContractViolation('room versions must be non-negative');
    }
    if (status == RoomCommandStatus.accepted &&
        roomVersionBefore != null &&
        roomVersionAfter != roomVersionBefore! + 1) {
      throw const RoomContractViolation(
        'Accepted room mutation must increment roomVersion once',
      );
    }
    if (status == RoomCommandStatus.rejected &&
        (errorCode == null || errorCode!.isEmpty)) {
      throw const RoomContractViolation(
        'Rejected RoomCommand requires a safe errorCode',
      );
    }
    if (gameId != null) _identifier(gameId!, 'gameId');
  }

  factory RoomCommandResult.fromJson(Map<String, Object?> json) {
    try {
      return _$RoomCommandResultFromJson(json);
    } on RoomContractViolation {
      rethrow;
    } on Object {
      throw const RoomContractViolation('Invalid RoomCommandResult JSON');
    }
  }

  @JsonKey(required: true)
  final String commandId;
  @JsonKey(required: true)
  final RoomCommandStatus status;
  @JsonKey(fromJson: _optionalInteger)
  final int? roomVersionBefore;
  @JsonKey(fromJson: _optionalInteger)
  final int? roomVersionAfter;
  final String? errorCode;
  final Map<String, Object?>? roomSnapshot;
  final String? gameId;
  @JsonKey(required: true, fromJson: _requiredUtcDate)
  final DateTime serverProcessedAt;

  Map<String, Object?> toJson() => _$RoomCommandResultToJson(this);

  String toCanonicalJson() => _canonicalJson(toJson());
}

// Generated decoding must preserve the existing integer-only boundary. The
// generator's default num.toInt conversion would silently truncate doubles.
int _requiredInteger(Object? value) {
  if (value is int) return value;
  throw const RoomContractViolation('Room contract requires an integer');
}

int? _optionalInteger(Object? value) =>
    value == null ? null : _requiredInteger(value);

DateTime _requiredUtcDate(Object? value) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw const RoomContractViolation('Room contract requires a timestamp');
}

DateTime? _optionalUtcDate(Object? value) =>
    value == null ? null : _requiredUtcDate(value);

Map<String, Object?> _immutableJson(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable(
      jsonDecode(_canonicalJson(value)) as Map<String, Object?>,
    );

String _canonicalJson(Map<String, Object?> value) =>
    jsonEncode(_normalizeJson(value));

Object? _normalizeJson(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is num) {
    throw const RoomContractViolation(
      'Room contract numeric material must use integers only',
    );
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_normalizeJson));
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final key in keys) key: _normalizeJson(value[key]),
    });
  }
  throw RoomContractViolation(
    'Unsupported room JSON value: ${value.runtimeType}',
  );
}

void _identifier(String value, String field) {
  if (value.isEmpty) {
    throw RoomContractViolation('$field must not be empty');
  }
}
