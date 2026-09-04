import 'client_authority.dart';

/// Minimal wire surface implemented by HTTP/Firebase infrastructure.
///
/// Authentication stays out-of-band. The maps crossing this boundary contain
/// only the public Authority protocol and can be backed by local emulators.
abstract interface class AuthorityWireTransport {
  Future<Map<String, Object?>> sendCommand(Map<String, Object?> request);

  Future<Map<String, Object?>> reconnect(Map<String, Object?> request);

  Stream<Map<String, Object?>> watchPublicGame(String gameId);

  Stream<Map<String, Object?>> watchPublicRoom(String roomId);
}

/// Concrete adapter behind the Flutter-facing Authority ports.
///
/// It preserves command identity byte-for-byte, converts wire data into the
/// privacy-validating public models, and never exposes a client state upload.
final class WireAuthorityClient
    implements
        CommandGateway,
        AuthoritySnapshotRepository,
        AuthorityRoomSnapshotRepository {
  const WireAuthorityClient(this._transport);

  final AuthorityWireTransport _transport;

  @override
  Future<AuthorityCommandReply> send(AuthorityCommandRequest request) async {
    final response = await _transport.sendCommand(request.toWireJson());
    return _commandReply(response);
  }

  @override
  Stream<AuthorityPublicSnapshot> watchGame(String gameId) {
    if (gameId.isEmpty) {
      throw const ClientAuthorityContractViolation('invalidSnapshotGameId');
    }
    return _transport.watchPublicGame(gameId).map(AuthorityPublicSnapshot.new);
  }

  @override
  Stream<AuthorityPublicRoomSnapshot> watchRoom(String roomId) {
    if (roomId.isEmpty) {
      throw const ClientAuthorityContractViolation('invalidRoomSnapshotRoomId');
    }
    return _transport
        .watchPublicRoom(roomId)
        .map(AuthorityPublicRoomSnapshot.new);
  }

  @override
  Future<AuthorityReconnectReply> reconnect(
    AuthorityReconnectRequest request,
  ) async {
    final response = await _transport.reconnect(request.toWireJson());
    return _reconnectReply(response);
  }
}

AuthorityCommandReply _commandReply(Map<String, Object?> value) {
  final status = _enumByWire(
    AuthorityCommandStatus.values,
    value['status'],
    (item) => item.wireValue,
    'invalidReplyStatus',
  );
  final snapshot = value['snapshot'];
  final publicResult = value['publicResult'];
  return AuthorityCommandReply(
    commandId: _string(value, 'commandId', 'invalidReplyCommandId'),
    status: status,
    versionBefore: _nonNegativeInt(
      value,
      'versionBefore',
      'invalidReplyVersion',
    ),
    versionAfter: _nonNegativeInt(value, 'versionAfter', 'invalidReplyVersion'),
    errorCode: value['errorCode'] as String?,
    publicResult: publicResult == null
        ? const <String, Object?>{}
        : _object(publicResult, 'invalidPublicResult'),
    snapshot: snapshot == null
        ? null
        : AuthorityPublicSnapshot(_object(snapshot, 'invalidSnapshot')),
  );
}

AuthorityReconnectReply _reconnectReply(Map<String, Object?> value) {
  final disposition = _enumByWire(
    ReconnectDisposition.values,
    value['disposition'],
    (item) => item.wireValue,
    'invalidReconnectDisposition',
  );
  final resolutionValue = value['commandResolution'];
  return AuthorityReconnectReply(
    disposition: disposition,
    snapshot: AuthorityPublicSnapshot(
      _object(value['snapshot'], 'invalidSnapshot'),
    ),
    commandResolution: resolutionValue == null
        ? null
        : _resolution(_object(resolutionValue, 'invalidCommandResolution')),
  );
}

ReconnectCommandResolution _resolution(Map<String, Object?> value) {
  final identityValue = _object(value['identity'], 'invalidUncertainIdentity');
  final action = _enumByWire(
    CommandResolutionAction.values,
    value['action'],
    (item) => item.wireValue,
    'invalidResolutionAction',
  );
  final publicResult = value['publicResult'];
  return ReconnectCommandResolution(
    identity: UncertainCommandIdentity(
      commandId: _string(
        identityValue,
        'commandId',
        'invalidUncertainCommandId',
      ),
      inputHashVersion: _nonNegativeInt(
        identityValue,
        'inputHashVersion',
        'unsupportedInputHashVersion',
      ),
      inputHash: _string(identityValue, 'inputHash', 'invalidInputHash'),
    ),
    action: action,
    publicResult: publicResult == null
        ? null
        : _object(publicResult, 'invalidPublicResult'),
    errorCode: value['errorCode'] as String?,
  );
}

T _enumByWire<T>(
  List<T> values,
  Object? wire,
  String Function(T item) selector,
  String code,
) {
  for (final value in values) {
    if (selector(value) == wire) return value;
  }
  throw ClientAuthorityContractViolation(code);
}

Map<String, Object?> _object(Object? value, String code) {
  if (value is Map<String, Object?>) return value;
  throw ClientAuthorityContractViolation(code);
}

String _string(Map<String, Object?> value, String key, String code) {
  final candidate = value[key];
  if (candidate is String && candidate.isNotEmpty) return candidate;
  throw ClientAuthorityContractViolation(code);
}

int _nonNegativeInt(Map<String, Object?> value, String key, String code) {
  final candidate = value[key];
  if (candidate is int && candidate >= 0) return candidate;
  throw ClientAuthorityContractViolation(code);
}
