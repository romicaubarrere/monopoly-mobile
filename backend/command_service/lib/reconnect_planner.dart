import 'package:board_game_core/game_core.dart';

final class AuthorityReconnectViolation implements Exception {
  const AuthorityReconnectViolation(this.code);

  final String code;

  @override
  String toString() => 'AuthorityReconnectViolation: $code';
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

/// Client-held identity for one command whose acknowledgement is uncertain.
///
/// The full payload, authentication material and transport metadata are not
/// needed during reconciliation. A retry still uses the original commandId and
/// semantic fingerprint; Authority never manufactures a replacement command.
final class UncertainCommandIdentity {
  UncertainCommandIdentity({
    required this.commandId,
    required this.inputHashVersion,
    required this.inputHash,
  }) {
    if (commandId.isEmpty) {
      throw const AuthorityReconnectViolation('invalidCommandId');
    }
    if (inputHashVersion != 1) {
      throw const AuthorityReconnectViolation('unsupportedInputHashVersion');
    }
    if (!_sha256Pattern.hasMatch(inputHash)) {
      throw const AuthorityReconnectViolation('invalidInputHash');
    }
  }

  final String commandId;
  final int inputHashVersion;
  final String inputHash;
}

/// Public subset of a durable operation-store record.
///
/// The persistence adapter must not place request payloads, tokens, direct UID
/// values or private RNG material in [publicResult].
final class DurableCommandReceipt {
  DurableCommandReceipt({
    required this.commandId,
    required this.inputHashVersion,
    required this.inputHash,
    required this.publicResult,
  }) {
    if (commandId.isEmpty ||
        inputHashVersion != 1 ||
        !_sha256Pattern.hasMatch(inputHash)) {
      throw const AuthorityReconnectViolation('invalidDurableReceipt');
    }
    final status = publicResult['status'];
    if (status != 'accepted' && status != 'rejected') {
      throw const AuthorityReconnectViolation('invalidDurableReceipt');
    }
    CanonicalDomainJson.encode(publicResult);
  }

  final String commandId;
  final int inputHashVersion;
  final String inputHash;
  final Map<String, Object?> publicResult;
}

/// Replacement snapshot and optional uncertain-command resolution.
///
/// There is deliberately no client snapshot input: reconnect is always
/// authority read + validation + replacement, never a two-way merge.
final class AuthorityReconnectPlan {
  const AuthorityReconnectPlan({
    required this.disposition,
    required this.authoritativeState,
    this.commandResolution,
  });

  final ReconnectDisposition disposition;
  final PublicGameState authoritativeState;
  final Map<String, Object?>? commandResolution;

  Map<String, Object?> toPublicJson() => <String, Object?>{
    'status': disposition.wireValue,
    'schemaVersion': authoritativeState.header.schemaVersion,
    'stateVersion': authoritativeState.header.stateVersion,
    'snapshot': authoritativeState.toJson(),
    if (commandResolution != null) 'commandResolution': commandResolution,
  };

  String toCanonicalPublicJson() => CanonicalDomainJson.encode(toPublicJson());
}

/// Authority-side reconnect planning for VP0.
///
/// The caller loads membership, the latest public snapshot and (when present)
/// the durable operation record in one consistent read boundary. This planner
/// then proves whether the client is current, must replace its snapshot, can
/// resolve a lost acknowledgement, or must retry the same command identity.
abstract final class AuthorityReconnectPlanner {
  static AuthorityReconnectPlan reconcile({
    required String authenticatedActorUid,
    required String actorPlayerId,
    required Map<String, String> memberUidByPlayerId,
    required int clientStateVersion,
    required PublicGameState authoritativeState,
    UncertainCommandIdentity? uncertainCommand,
    DurableCommandReceipt? durableReceipt,
  }) {
    if (authenticatedActorUid.isEmpty ||
        memberUidByPlayerId[actorPlayerId] != authenticatedActorUid) {
      throw const AuthorityReconnectViolation('actorNotAuthenticatedMember');
    }
    if (clientStateVersion < 0) {
      throw const AuthorityReconnectViolation('invalidClientStateVersion');
    }
    if (clientStateVersion > authoritativeState.header.stateVersion) {
      throw const AuthorityReconnectViolation('clientVersionAheadOfAuthority');
    }
    if (durableReceipt != null && uncertainCommand == null) {
      throw const AuthorityReconnectViolation('orphanDurableReceipt');
    }

    final baseDisposition =
        clientStateVersion == authoritativeState.header.stateVersion
        ? ReconnectDisposition.upToDate
        : ReconnectDisposition.snapshotAdvanced;
    if (uncertainCommand == null) {
      return AuthorityReconnectPlan(
        disposition: baseDisposition,
        authoritativeState: authoritativeState,
      );
    }
    if (durableReceipt == null) {
      return AuthorityReconnectPlan(
        disposition: ReconnectDisposition.retrySameCommand,
        authoritativeState: authoritativeState,
        commandResolution: <String, Object?>{
          'commandId': uncertainCommand.commandId,
          'inputHashVersion': uncertainCommand.inputHashVersion,
          'action': 'retrySameCommand',
        },
      );
    }
    if (durableReceipt.commandId != uncertainCommand.commandId ||
        durableReceipt.inputHashVersion != uncertainCommand.inputHashVersion ||
        durableReceipt.inputHash != uncertainCommand.inputHash) {
      return AuthorityReconnectPlan(
        disposition: ReconnectDisposition.semanticCollision,
        authoritativeState: authoritativeState,
        commandResolution: <String, Object?>{
          'commandId': uncertainCommand.commandId,
          'inputHashVersion': uncertainCommand.inputHashVersion,
          'action': 'failClosed',
          'errorCode': 'commandIdCollision',
        },
      );
    }

    final accepted = durableReceipt.publicResult['status'] == 'accepted';
    return AuthorityReconnectPlan(
      disposition: accepted
          ? ReconnectDisposition.uncertainConfirmed
          : ReconnectDisposition.uncertainRejected,
      authoritativeState: authoritativeState,
      commandResolution: <String, Object?>{
        'commandId': uncertainCommand.commandId,
        'inputHashVersion': uncertainCommand.inputHashVersion,
        'action': 'useDurableResult',
        'result': durableReceipt.publicResult,
      },
    );
  }
}

final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
