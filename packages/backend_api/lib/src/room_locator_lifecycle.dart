enum RoomLocatorResult { available, roomUnavailable }

final class RoomCodeLocator {
  const RoomCodeLocator({
    required this.codeHash,
    required this.roomId,
    required this.expiresAtMs,
    required this.roomClosed,
  });

  final String codeHash;
  final String roomId;
  final int expiresAtMs;
  final bool roomClosed;

  bool isExpiredAt(int serverNowMs) => expiresAtMs <= serverNowMs;

  RoomLocatorResult resolveForJoin({required int serverNowMs}) {
    if (roomClosed || isExpiredAt(serverNowMs)) {
      return RoomLocatorResult.roomUnavailable;
    }
    return RoomLocatorResult.available;
  }
}

final class RoomCodeClaim {
  const RoomCodeClaim({required this.codeHash, required this.roomId});

  final String codeHash;
  final String roomId;
}

/// Transaction-scoped model for TV-41.
///
/// Production persistence must execute [claim] inside the same Firestore
/// transaction that reads and replaces the locator document. This model keeps
/// correctness independent from TTL/physical deletion.
final class RoomCodeClaimTransaction {
  RoomCodeClaimTransaction({RoomCodeLocator? current}) : this._(current);

  RoomCodeClaimTransaction._(this._current);

  RoomCodeLocator? _current;

  RoomCodeClaim? claim({
    required String codeHash,
    required String roomId,
    required int serverNowMs,
    required int expiresAtMs,
  }) {
    final current = _current;
    if (current != null &&
        current.codeHash == codeHash &&
        !current.roomClosed &&
        !current.isExpiredAt(serverNowMs)) {
      return null;
    }

    _current = RoomCodeLocator(
      codeHash: codeHash,
      roomId: roomId,
      expiresAtMs: expiresAtMs,
      roomClosed: false,
    );
    return RoomCodeClaim(codeHash: codeHash, roomId: roomId);
  }

  RoomCodeLocator? get current => _current;
}
