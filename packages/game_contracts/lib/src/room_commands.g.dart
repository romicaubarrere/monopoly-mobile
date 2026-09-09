// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_commands.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RoomCommand _$RoomCommandFromJson(Map<String, dynamic> json) {
  $checkKeys(
    json,
    allowedKeys: const [
      'commandId',
      'schemaVersion',
      'expectedRoomVersion',
      'clientInstanceId',
      'type',
      'payload',
      'sentAt',
    ],
    requiredKeys: const [
      'commandId',
      'schemaVersion',
      'clientInstanceId',
      'type',
      'payload',
    ],
  );
  return RoomCommand(
    commandId: json['commandId'] as String,
    schemaVersion: _requiredInteger(json['schemaVersion']),
    expectedRoomVersion: _optionalInteger(json['expectedRoomVersion']),
    clientInstanceId: json['clientInstanceId'] as String,
    type: $enumDecode(_$RoomCommandTypeEnumMap, json['type']),
    payload: json['payload'] as Map<String, dynamic>,
    sentAt: _optionalUtcDate(json['sentAt']),
  );
}

Map<String, dynamic> _$RoomCommandToJson(RoomCommand instance) =>
    <String, dynamic>{
      'commandId': instance.commandId,
      'schemaVersion': instance.schemaVersion,
      'expectedRoomVersion': ?instance.expectedRoomVersion,
      'clientInstanceId': instance.clientInstanceId,
      'type': _$RoomCommandTypeEnumMap[instance.type]!,
      'payload': instance.payload,
      'sentAt': ?instance.sentAt?.toIso8601String(),
    };

const _$RoomCommandTypeEnumMap = {
  RoomCommandType.createRoom: 'CreateRoom',
  RoomCommandType.joinRoom: 'JoinRoom',
  RoomCommandType.leaveRoom: 'LeaveRoom',
  RoomCommandType.setReady: 'SetReady',
  RoomCommandType.setPreset: 'SetPreset',
  RoomCommandType.startGame: 'StartGame',
};

RoomCommandResult _$RoomCommandResultFromJson(Map<String, dynamic> json) {
  $checkKeys(
    json,
    allowedKeys: const [
      'commandId',
      'status',
      'roomVersionBefore',
      'roomVersionAfter',
      'errorCode',
      'roomSnapshot',
      'gameId',
      'serverProcessedAt',
    ],
    requiredKeys: const ['commandId', 'status', 'serverProcessedAt'],
  );
  return RoomCommandResult(
    commandId: json['commandId'] as String,
    status: $enumDecode(_$RoomCommandStatusEnumMap, json['status']),
    roomVersionBefore: _optionalInteger(json['roomVersionBefore']),
    roomVersionAfter: _optionalInteger(json['roomVersionAfter']),
    errorCode: json['errorCode'] as String?,
    roomSnapshot: json['roomSnapshot'] as Map<String, dynamic>?,
    gameId: json['gameId'] as String?,
    serverProcessedAt: _requiredUtcDate(json['serverProcessedAt']),
  );
}

Map<String, dynamic> _$RoomCommandResultToJson(RoomCommandResult instance) =>
    <String, dynamic>{
      'commandId': instance.commandId,
      'status': _$RoomCommandStatusEnumMap[instance.status]!,
      'roomVersionBefore': ?instance.roomVersionBefore,
      'roomVersionAfter': ?instance.roomVersionAfter,
      'errorCode': ?instance.errorCode,
      'roomSnapshot': ?instance.roomSnapshot,
      'gameId': ?instance.gameId,
      'serverProcessedAt': instance.serverProcessedAt.toIso8601String(),
    };

const _$RoomCommandStatusEnumMap = {
  RoomCommandStatus.accepted: 'accepted',
  RoomCommandStatus.rejected: 'rejected',
  RoomCommandStatus.duplicate: 'duplicate',
};
