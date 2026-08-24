import 'dart:convert';
import 'dart:typed_data';

import '../lib/security/firebase_identity_verifier.dart';
import '../lib/security/membership_authorizer.dart';

Future<void> main() async {
  final now = DateTime.utc(2026, 8, 24, 2, 10);
  final signatureVerifier = _RecordingSignatureVerifier(valid: true);
  final verifier = FirebaseIdentityVerifier(
    projectId: 'demo-board-game-local',
    signatureVerifier: signatureVerifier,
    now: () => now,
  );

  final token = _token(
    header: <String, Object?>{'alg': 'RS256', 'kid': 'synthetic-key-id'},
    payload: <String, Object?>{
      'aud': 'demo-board-game-local',
      'iss': 'https://securetoken.google.com/demo-board-game-local',
      'exp': now.millisecondsSinceEpoch ~/ 1000 + 300,
      'iat': now.millisecondsSinceEpoch ~/ 1000 - 10,
      'auth_time': now.millisecondsSinceEpoch ~/ 1000 - 20,
      'sub': 'synthetic-uid',
    },
  );
  final identity = await verifier.verify(token);
  _expect(identity.uid == 'synthetic-uid', 'verified uid mismatch');
  _expect(signatureVerifier.calls == 1, 'signature verifier must run once');
  _expect(signatureVerifier.lastKid == 'synthetic-key-id', 'kid mismatch');

  await _expectIdentityFailure(
    FirebaseIdentityVerifier(
      projectId: 'demo-board-game-local',
      signatureVerifier: signatureVerifier,
      now: () => now,
    ),
    _token(
      header: <String, Object?>{'alg': 'HS256', 'kid': 'synthetic-key-id'},
      payload: _validPayload(now),
    ),
    'unsupported_algorithm',
  );
  await _expectIdentityFailure(
    verifier,
    _token(
      header: <String, Object?>{'alg': 'RS256', 'kid': 'synthetic-key-id'},
      payload: <String, Object?>{
        ..._validPayload(now),
        'aud': 'wrong-project',
      },
    ),
    'invalid_audience',
  );
  await _expectIdentityFailure(
    FirebaseIdentityVerifier(
      projectId: 'demo-board-game-local',
      signatureVerifier: _RecordingSignatureVerifier(valid: false),
      now: () => now,
    ),
    token,
    'invalid_signature',
  );

  final authorizer = MembershipAuthorizer(
    _MemoryMembershipStore(
      const AuthorityMembership(
        uid: 'synthetic-uid',
        gameId: 'game-synthetic',
        playerId: 'player-synthetic',
        isHost: true,
      ),
    ),
  );
  final membership = await authorizer.requireMember(
    authenticatedUid: identity.uid,
    gameId: 'game-synthetic',
    claimedPlayerId: 'player-synthetic',
    requireHost: true,
  );
  _expect(membership.isHost, 'host membership expected');

  await _expectMembershipFailure(
    authorizer,
    authenticatedUid: identity.uid,
    gameId: 'game-synthetic',
    claimedPlayerId: 'different-player',
    code: 'actor_mismatch',
  );
}

Map<String, Object?> _validPayload(DateTime now) => <String, Object?>{
  'aud': 'demo-board-game-local',
  'iss': 'https://securetoken.google.com/demo-board-game-local',
  'exp': now.millisecondsSinceEpoch ~/ 1000 + 300,
  'iat': now.millisecondsSinceEpoch ~/ 1000 - 10,
  'auth_time': now.millisecondsSinceEpoch ~/ 1000 - 20,
  'sub': 'synthetic-uid',
};

String _token({
  required Map<String, Object?> header,
  required Map<String, Object?> payload,
}) {
  String encode(Object value) => base64Url
      .encode(utf8.encode(jsonEncode(value)))
      .replaceAll('=', '');
  final signature = base64Url.encode(<int>[1, 2, 3]).replaceAll('=', '');
  return '${encode(header)}.${encode(payload)}.$signature';
}

Future<void> _expectIdentityFailure(
  FirebaseIdentityVerifier verifier,
  String token,
  String code,
) async {
  try {
    await verifier.verify(token);
  } on IdentityVerificationException catch (error) {
    _expect(error.code == code, 'expected $code, got ${error.code}');
    return;
  }
  throw StateError('expected identity failure: $code');
}

Future<void> _expectMembershipFailure(
  MembershipAuthorizer authorizer, {
  required String authenticatedUid,
  required String gameId,
  required String claimedPlayerId,
  required String code,
}) async {
  try {
    await authorizer.requireMember(
      authenticatedUid: authenticatedUid,
      gameId: gameId,
      claimedPlayerId: claimedPlayerId,
    );
  } on MembershipAuthorizationException catch (error) {
    _expect(error.code == code, 'expected $code, got ${error.code}');
    return;
  }
  throw StateError('expected membership failure: $code');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

final class _RecordingSignatureVerifier implements IdTokenSignatureVerifier {
  _RecordingSignatureVerifier({required this.valid});

  final bool valid;
  int calls = 0;
  String? lastKid;

  @override
  Future<bool> verify({
    required String kid,
    required Uint8List signingInput,
    required Uint8List signature,
  }) async {
    calls += 1;
    lastKid = kid;
    return valid && signingInput.isNotEmpty && signature.isNotEmpty;
  }
}

final class _MemoryMembershipStore implements MembershipStore {
  const _MemoryMembershipStore(this.membership);

  final AuthorityMembership membership;

  @override
  Future<AuthorityMembership?> findMembership({
    required String uid,
    required String gameId,
  }) async {
    if (membership.uid == uid && membership.gameId == gameId) {
      return membership;
    }
    return null;
  }
}
