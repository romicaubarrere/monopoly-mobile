import 'dart:convert';

import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';

import 'semantic_fingerprint.dart';

final class ClientAuthorityContractViolation implements Exception {
  const ClientAuthorityContractViolation(this.code);

  final String code;

  @override
  String toString() => 'ClientAuthorityContractViolation: $code';
}

enum AuthorityCommandFamily {
  room('room'),
  game('game');

  const AuthorityCommandFamily(this.wireValue);

  final String wireValue;
}

enum AuthorityCommandStatus {
  accepted('accepted'),
  rejected('rejected'),
  duplicate('duplicate');

  const AuthorityCommandStatus(this.wireValue);

  final String wireValue;
}

/// Transport-neutral client request for one authoritative command.
///
/// The embedded command remains the canonical RoomCommand/GameCommand wire
/// envelope. Authentication is deliberately absent: a concrete transport adds
/// credentials out-of-band and Authority derives the actor UID from them.
/// [inputHash] covers semantic material only, so retrying after a lost ACK must
/// reuse this exact request instead of minting a new command identity.
final class AuthorityCommandRequest {
  AuthorityCommandRequest._({
    required this.family,
    required Map<String, Object?> command,
  }) : command = _immutableJson(command),
       inputHashVersion = ProtocolFoundation.inputHashVersion,
       inputHash = SemanticFingerprintV1.sha256Hex(
         _semanticMaterial(family, command),
       ) {
    _validateCommand(family, this.command);
  }

  factory AuthorityCommandRequest.room(RoomCommand command) =>
      AuthorityCommandRequest._(
        family: AuthorityCommandFamily.room,
        command: command.toJson(),
      );

  /// Builds the client wire envelope from Engine's canonical GameCommand.
  ///
  /// Importing the pure-Dart contract does not run Engine logic in Flutter. It
  /// prevents this transport boundary from maintaining a second command schema
  /// or command-type catalog.
  factory AuthorityCommandRequest.game(GameCommand command) =>
      AuthorityCommandRequest._(
        family: AuthorityCommandFamily.game,
        command: command.toJson(),
      );

  final AuthorityCommandFamily family;
  final Map<String, Object?> command;
  final int inputHashVersion;
  final String inputHash;

  String get commandId => command['commandId']! as String;

  Map<String, Object?> toWireJson() => <String, Object?>{
    'family': family.wireValue,
    'inputHashVersion': inputHashVersion,
    'inputHash': inputHash,
    'command': command,
  };

  String toCanonicalWireJson() =>
      SemanticFingerprintV1.canonicalJson(toWireJson());

  UncertainCommandIdentity get uncertainIdentity => UncertainCommandIdentity(
    commandId: commandId,
    inputHashVersion: inputHashVersion,
    inputHash: inputHash,
  );
}

/// Complete public game snapshot received from Authority.
///
/// The client replaces its cached snapshot with this value. There is no API for
/// submitting or merging client-owned state. Full domain validation remains in
/// Engine/Authority; this boundary validates protocol versions and privacy.
final class AuthorityPublicSnapshot {
  AuthorityPublicSnapshot(Map<String, Object?> snapshot)
    : snapshot = _immutableJson(snapshot) {
    final schemaVersion = this.snapshot['schemaVersion'];
    final stateVersion = this.snapshot['stateVersion'];
    final gameId = this.snapshot['gameId'];
    if (schemaVersion != 1) {
      throw const ClientAuthorityContractViolation(
        'unsupportedSnapshotSchemaVersion',
      );
    }
    if (stateVersion is! int || stateVersion < 0) {
      throw const ClientAuthorityContractViolation('invalidSnapshotVersion');
    }
    if (gameId is! String || gameId.isEmpty) {
      throw const ClientAuthorityContractViolation('invalidSnapshotGameId');
    }
    _rejectPrivateMaterial(this.snapshot);
  }

  final Map<String, Object?> snapshot;

  int get schemaVersion => snapshot['schemaVersion']! as int;
  int get stateVersion => snapshot['stateVersion']! as int;
  String get gameId => snapshot['gameId']! as String;

  String toCanonicalJson() => SemanticFingerprintV1.canonicalJson(snapshot);
}

/// Safe command outcome returned to Flutter.
///
/// Accepted results advance exactly once; rejections do not mutate; duplicates
/// replay the durable result and may report either delta. Flutter never applies
/// events optimistically and instead converges on [snapshot] or its snapshot
/// stream.
final class AuthorityCommandReply {
  AuthorityCommandReply({
    required this.commandId,
    required this.status,
    required this.versionBefore,
    required this.versionAfter,
    this.errorCode,
    Map<String, Object?> publicResult = const <String, Object?>{},
    this.snapshot,
  }) : publicResult = _immutableJson(publicResult) {
    _identifier(commandId, 'invalidReplyCommandId');
    if (versionBefore < 0 || versionAfter < versionBefore) {
      throw const ClientAuthorityContractViolation('invalidReplyVersion');
    }
    final delta = versionAfter - versionBefore;
    if (delta > 1 ||
        status == AuthorityCommandStatus.accepted && delta != 1 ||
        status == AuthorityCommandStatus.rejected && delta != 0) {
      throw const ClientAuthorityContractViolation('invalidReplyVersion');
    }
    if (status == AuthorityCommandStatus.rejected &&
        (errorCode == null || errorCode!.isEmpty)) {
      throw const ClientAuthorityContractViolation('missingSafeErrorCode');
    }
    if (snapshot != null && snapshot!.stateVersion != versionAfter) {
      throw const ClientAuthorityContractViolation('replySnapshotMismatch');
    }
    _rejectPrivateMaterial(this.publicResult);
  }

  final String commandId;
  final AuthorityCommandStatus status;
  final int versionBefore;
  final int versionAfter;
  final String? errorCode;
  final Map<String, Object?> publicResult;
  final AuthorityPublicSnapshot? snapshot;
}

final class UncertainCommandIdentity {
  UncertainCommandIdentity({
    required this.commandId,
    required this.inputHashVersion,
    required this.inputHash,
  }) {
    _identifier(commandId, 'invalidUncertainCommandId');
    if (inputHashVersion != ProtocolFoundation.inputHashVersion) {
      throw const ClientAuthorityContractViolation(
        'unsupportedInputHashVersion',
      );
    }
    if (!_sha256Pattern.hasMatch(inputHash)) {
      throw const ClientAuthorityContractViolation('invalidInputHash');
    }
  }

  final String commandId;
  final int inputHashVersion;
  final String inputHash;

  Map<String, Object?> toWireJson() => <String, Object?>{
    'commandId': commandId,
    'inputHashVersion': inputHashVersion,
    'inputHash': inputHash,
  };
}

final class AuthorityReconnectRequest {
  AuthorityReconnectRequest({
    required this.gameId,
    required this.observedStateVersion,
    this.uncertainCommand,
  }) {
    _identifier(gameId, 'invalidReconnectGameId');
    if (observedStateVersion < 0) {
      throw const ClientAuthorityContractViolation(
        'invalidObservedStateVersion',
      );
    }
  }

  final String gameId;
  final int observedStateVersion;
  final UncertainCommandIdentity? uncertainCommand;

  Map<String, Object?> toWireJson() => <String, Object?>{
    'gameId': gameId,
    'observedStateVersion': observedStateVersion,
    if (uncertainCommand != null)
      'uncertainCommand': uncertainCommand!.toWireJson(),
  };
}

enum ReconnectDisposition {
  upToDate('upToDate'),
  snapshotAdvanced('snapshotAdvanced'),
  uncertainConfirmed('uncertainConfirmed'),
  uncertainRejected('uncertainRejected'),
  retrySameCommand('retrySameCommand'),
  semanticCollision('semanticCollision');

  const ReconnectDisposition(this.wireValue);

  final String wireValue;
}

enum CommandResolutionAction {
  useDurableResult('useDurableResult'),
  retrySameCommand('retrySameCommand'),
  failClosed('failClosed');

  const CommandResolutionAction(this.wireValue);

  final String wireValue;
}

final class ReconnectCommandResolution {
  ReconnectCommandResolution({
    required this.identity,
    required this.action,
    Map<String, Object?>? publicResult,
    this.errorCode,
  }) : publicResult = publicResult == null
           ? null
           : _immutableJson(publicResult) {
    if (action == CommandResolutionAction.useDurableResult &&
        this.publicResult == null) {
      throw const ClientAuthorityContractViolation('missingDurableResult');
    }
    if (action != CommandResolutionAction.useDurableResult &&
        this.publicResult != null) {
      throw const ClientAuthorityContractViolation('unexpectedDurableResult');
    }
    if (action == CommandResolutionAction.failClosed &&
        (errorCode == null || errorCode!.isEmpty)) {
      throw const ClientAuthorityContractViolation('missingSafeErrorCode');
    }
    if (this.publicResult != null) {
      _rejectPrivateMaterial(this.publicResult!);
    }
  }

  final UncertainCommandIdentity identity;
  final CommandResolutionAction action;
  final Map<String, Object?>? publicResult;
  final String? errorCode;
}

final class AuthorityReconnectReply {
  AuthorityReconnectReply({
    required this.disposition,
    required this.snapshot,
    this.commandResolution,
  }) {
    final expectedAction = switch (disposition) {
      ReconnectDisposition.uncertainConfirmed ||
      ReconnectDisposition.uncertainRejected =>
        CommandResolutionAction.useDurableResult,
      ReconnectDisposition.retrySameCommand =>
        CommandResolutionAction.retrySameCommand,
      ReconnectDisposition.semanticCollision =>
        CommandResolutionAction.failClosed,
      ReconnectDisposition.upToDate ||
      ReconnectDisposition.snapshotAdvanced => null,
    };
    if (expectedAction != commandResolution?.action) {
      throw const ClientAuthorityContractViolation(
        'reconnectResolutionMismatch',
      );
    }
  }

  final ReconnectDisposition disposition;
  final AuthorityPublicSnapshot snapshot;
  final ReconnectCommandResolution? commandResolution;
}

/// Port implemented by HTTP/Firebase infrastructure and consumed by Flutter.
///
/// A concrete adapter may attach authentication and transport metadata, but it
/// must send [request.command] and its command identity unchanged across retry.
abstract interface class CommandGateway {
  Future<AuthorityCommandReply> send(AuthorityCommandRequest request);
}

/// Flutter repository port for authoritative public state and reconnect.
///
/// Implementations expose replacement snapshots only. Private state and
/// client-to-authority snapshot merge are intentionally unrepresentable.
abstract interface class AuthoritySnapshotRepository {
  Stream<AuthorityPublicSnapshot> watchGame(String gameId);

  Future<AuthorityReconnectReply> reconnect(AuthorityReconnectRequest request);
}

Map<String, Object?> _semanticMaterial(
  AuthorityCommandFamily family,
  Map<String, Object?> command,
) {
  final payload = command['payload'];
  if (payload is! Map<String, Object?>) {
    throw const ClientAuthorityContractViolation('invalidCommandPayload');
  }
  if (family == AuthorityCommandFamily.game) {
    return <String, Object?>{
      'v': ProtocolFoundation.inputHashVersion,
      'family': family.wireValue,
      'type': command['type'],
      'target': command['gameId'],
      'expectedVersion': command['expectedStateVersion'],
      'actorPlayerId': command['actorPlayerId'],
      'payload': payload,
    };
  }
  return <String, Object?>{
    'v': ProtocolFoundation.inputHashVersion,
    'family': family.wireValue,
    'type': command['type'],
    'target': payload['roomId'] ?? payload['roomCode'] ?? 'new-room',
    'expectedVersion': command['expectedRoomVersion'],
    'payload': payload,
  };
}

void _validateCommand(
  AuthorityCommandFamily family,
  Map<String, Object?> command,
) {
  _identifier(command['commandId'], 'invalidCommandId');
  _identifier(command['clientInstanceId'], 'invalidClientInstanceId');
  _identifier(command['type'], 'invalidCommandType');
  if (command['schemaVersion'] != 1) {
    throw const ClientAuthorityContractViolation(
      'unsupportedCommandSchemaVersion',
    );
  }
  if (command['payload'] is! Map<String, Object?>) {
    throw const ClientAuthorityContractViolation('invalidCommandPayload');
  }
  if (family == AuthorityCommandFamily.game) {
    _identifier(command['gameId'], 'invalidGameId');
    _identifier(command['actorPlayerId'], 'invalidActorPlayerId');
    final expected = command['expectedStateVersion'];
    if (expected is! int || expected < 0) {
      throw const ClientAuthorityContractViolation('invalidExpectedVersion');
    }
  } else {
    final expected = command['expectedRoomVersion'];
    if (expected != null && (expected is! int || expected < 0)) {
      throw const ClientAuthorityContractViolation('invalidExpectedVersion');
    }
  }
  _rejectPrivateMaterial(command);
}

Map<String, Object?> _immutableJson(Map<String, Object?> source) {
  try {
    return _freezeJson(jsonDecode(SemanticFingerprintV1.canonicalJson(source)))
        as Map<String, Object?>;
  } on ArgumentError {
    throw const ClientAuthorityContractViolation('invalidJsonMaterial');
  }
}

Object? _freezeJson(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in value.entries) entry.key: _freezeJson(entry.value),
    });
  }
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_freezeJson));
  }
  return value;
}

void _identifier(Object? value, String code) {
  if (value is! String || value.isEmpty) {
    throw ClientAuthorityContractViolation(code);
  }
}

void _rejectPrivateMaterial(Object? value, [String? key]) {
  if (key != null && _privateKeys.contains(key.toLowerCase())) {
    throw const ClientAuthorityContractViolation('privateMaterialForbidden');
  }
  if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      _rejectPrivateMaterial(entry.value, entry.key);
    }
  } else if (value is List<Object?>) {
    for (final item in value) {
      _rejectPrivateMaterial(item);
    }
  }
}

const Set<String> _privateKeys = <String>{
  'authorization',
  'authtoken',
  'authenticatedactoruid',
  'actoruid',
  'gamesecrets',
  'memberuidbyplayerid',
  'memberuids',
  'privatedeckstate',
  'seed',
  'seedbytes',
  'streamcounters',
  'futuredeck',
  'futuredeckorder',
  'token',
  'uid',
};

final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
