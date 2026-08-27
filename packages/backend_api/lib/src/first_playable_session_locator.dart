import 'dart:convert';

import 'client_authority.dart';

typedef FirstPlayableSessionLocatorJsonRead = Future<String?> Function();
typedef FirstPlayableSessionLocatorJsonWrite = Future<void> Function(
  String? value,
);

/// Public identifiers required to restore authenticated Authority snapshots.
///
/// Actor membership, Firebase UID, versions and gameplay state are excluded;
/// restore obtains them again from Authority instead of trusting device state.
final class FirstPlayableSessionLocator {
  FirstPlayableSessionLocator({required String roomId, String? gameId})
    : roomId = _locatorId(roomId, 'invalidLocatorRoomId'),
      gameId = gameId == null
          ? null
          : _locatorId(gameId, 'invalidLocatorGameId');

  final String roomId;
  final String? gameId;

  Map<String, Object?> toWireJson() => <String, Object?>{
    'schemaVersion': 1,
    'roomId': roomId,
    if (gameId != null) 'gameId': gameId,
  };
}

abstract interface class FirstPlayableSessionLocatorStore {
  Future<FirstPlayableSessionLocator?> load();

  Future<void> save(FirstPlayableSessionLocator locator);
}

/// Canonical device persistence for the public room/game locator only.
final class JsonFirstPlayableSessionLocatorStore
    implements FirstPlayableSessionLocatorStore {
  JsonFirstPlayableSessionLocatorStore({
    required FirstPlayableSessionLocatorJsonRead read,
    required FirstPlayableSessionLocatorJsonWrite write,
  }) : this._(read, write);

  const JsonFirstPlayableSessionLocatorStore._(this._read, this._write);

  static const int _maximumStoredBytes = 4096;

  final FirstPlayableSessionLocatorJsonRead _read;
  final FirstPlayableSessionLocatorJsonWrite _write;

  @override
  Future<FirstPlayableSessionLocator?> load() async {
    final value = await _read();
    if (value == null) return null;
    if (value.isEmpty || utf8.encode(value).length > _maximumStoredBytes) {
      throw const ClientAuthorityContractViolation('sessionLocatorCorrupt');
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?> ||
          decoded['schemaVersion'] != 1 ||
          decoded.keys.any(
            (key) => !const <String>{
              'schemaVersion',
              'roomId',
              'gameId',
            }.contains(key),
          )) {
        throw const ClientAuthorityContractViolation('sessionLocatorCorrupt');
      }
      final roomId = decoded['roomId'];
      final gameId = decoded['gameId'];
      if (roomId is! String || gameId != null && gameId is! String) {
        throw const ClientAuthorityContractViolation('sessionLocatorCorrupt');
      }
      final locator = FirstPlayableSessionLocator(
        roomId: roomId,
        gameId: gameId as String?,
      );
      if (jsonEncode(locator.toWireJson()) != value) {
        throw const ClientAuthorityContractViolation('sessionLocatorCorrupt');
      }
      return locator;
    } on ClientAuthorityContractViolation {
      throw const ClientAuthorityContractViolation('sessionLocatorCorrupt');
    } on FormatException {
      throw const ClientAuthorityContractViolation('sessionLocatorCorrupt');
    }
  }

  @override
  Future<void> save(FirstPlayableSessionLocator locator) =>
      _write(jsonEncode(locator.toWireJson()));
}

String _locatorId(String value, String code) {
  if (value.isEmpty ||
      value.length > 128 ||
      value.trim() != value ||
      value.contains('/')) {
    throw ClientAuthorityContractViolation(code);
  }
  return value;
}
