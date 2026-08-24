final class AuthorityMembership {
  const AuthorityMembership({
    required this.uid,
    required this.gameId,
    required this.playerId,
    required this.isHost,
  });

  final String uid;
  final String gameId;
  final String playerId;
  final bool isHost;
}

abstract interface class MembershipStore {
  Future<AuthorityMembership?> findMembership({
    required String uid,
    required String gameId,
  });
}

final class MembershipAuthorizationException implements Exception {
  const MembershipAuthorizationException(this.code);

  final String code;

  @override
  String toString() => 'MembershipAuthorizationException($code)';
}

/// Authority-side membership check kept separate from token authentication.
final class MembershipAuthorizer {
  const MembershipAuthorizer(this._store);

  final MembershipStore _store;

  Future<AuthorityMembership> requireMember({
    required String authenticatedUid,
    required String gameId,
    String? claimedPlayerId,
    bool requireHost = false,
  }) async {
    if (authenticatedUid.isEmpty || gameId.isEmpty) {
      throw const MembershipAuthorizationException('invalid_identity_scope');
    }

    final membership = await _store.findMembership(
      uid: authenticatedUid,
      gameId: gameId,
    );
    if (membership == null || membership.uid != authenticatedUid) {
      throw const MembershipAuthorizationException('not_a_member');
    }
    if (membership.gameId != gameId) {
      throw const MembershipAuthorizationException('membership_scope_mismatch');
    }
    if (claimedPlayerId != null && membership.playerId != claimedPlayerId) {
      throw const MembershipAuthorizationException('actor_mismatch');
    }
    if (requireHost && !membership.isHost) {
      throw const MembershipAuthorizationException('host_required');
    }

    return membership;
  }
}
