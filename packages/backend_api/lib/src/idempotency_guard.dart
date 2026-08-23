/// Persisted identity needed to decide duplicate vs collision before gameplay.
final class PersistedCommandIdentity {
  const PersistedCommandIdentity({
    required this.actorUid,
    required this.inputHashVersion,
    required this.inputHash,
  });

  final String actorUid;
  final int inputHashVersion;
  final String inputHash;
}

enum IdempotencyDisposition { newCommand, duplicate, commandIdCollision }

/// Pure pre-engine idempotency decision.
///
/// A collision or duplicate never invokes [applyNewCommand]. Persistence of the
/// resulting record and gameplay mutation must later share one authority
/// transaction; this helper does not claim Firestore atomicity by itself.
abstract final class IdempotencyGuard {
  static IdempotencyDisposition classify({
    required PersistedCommandIdentity? existing,
    required String actorUid,
    required int inputHashVersion,
    required String inputHash,
  }) {
    if (existing == null) {
      return IdempotencyDisposition.newCommand;
    }

    if (existing.actorUid == actorUid &&
        existing.inputHashVersion == inputHashVersion &&
        existing.inputHash == inputHash) {
      return IdempotencyDisposition.duplicate;
    }

    return IdempotencyDisposition.commandIdCollision;
  }

  static T? executeIfNew<T>({
    required PersistedCommandIdentity? existing,
    required String actorUid,
    required int inputHashVersion,
    required String inputHash,
    required T Function() applyNewCommand,
  }) {
    final IdempotencyDisposition disposition = classify(
      existing: existing,
      actorUid: actorUid,
      inputHashVersion: inputHashVersion,
      inputHash: inputHash,
    );

    if (disposition != IdempotencyDisposition.newCommand) {
      return null;
    }
    return applyNewCommand();
  }
}
