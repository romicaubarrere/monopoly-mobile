import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_core/game_core.dart';

final class AuthorityBankruptcyViolation implements Exception {
  const AuthorityBankruptcyViolation(this.code);

  final String code;

  @override
  String toString() => 'AuthorityBankruptcyViolation: $code';
}

/// Atomic persistence plan produced from the canonical bankruptcy Engine.
///
/// The durable adapter commits [stateAfter] and [safeResultSummary] together.
/// Bankruptcy consumes no randomness, so an adapter must leave `gameSecrets`
/// byte-for-byte unchanged.
final class AuthorityBankruptcyPlan {
  const AuthorityBankruptcyPlan(this.enginePlan);

  final BankruptcyPlan enginePlan;

  PublicGameState get stateAfter => enginePlan.stateAfter;

  Map<String, Object?> get safeResultSummary => <String, Object?>{
    'commandId': enginePlan.commandId,
    'status': 'accepted',
    'stateVersionBefore': enginePlan.stateVersionBefore,
    'stateVersionAfter': enginePlan.stateVersionAfter,
    'bankruptcyDeclared': enginePlan.bankruptcyDeclared,
    'events': enginePlan.events
        .map((event) => event.toJson())
        .toList(growable: false),
  };
}

sealed class AuthorityBankruptcyEvaluation {
  const AuthorityBankruptcyEvaluation();

  bool get accepted;
  Map<String, Object?> get publicResult;
}

final class AuthorityBankruptcyAccepted extends AuthorityBankruptcyEvaluation {
  const AuthorityBankruptcyAccepted(this.plan);

  final AuthorityBankruptcyPlan plan;

  @override
  bool get accepted => true;

  @override
  Map<String, Object?> get publicResult => plan.safeResultSummary;
}

final class AuthorityBankruptcyRejected extends AuthorityBankruptcyEvaluation {
  const AuthorityBankruptcyRejected(this.rejection);

  final BankruptcyRejection rejection;

  @override
  bool get accepted => false;

  @override
  Map<String, Object?> get publicResult => rejection.toPublicJson();
}

final class AuthorityBankruptcyNoOp extends AuthorityBankruptcyEvaluation {
  const AuthorityBankruptcyNoOp({required this.reason});

  final String reason;

  @override
  bool get accepted => false;

  @override
  Map<String, Object?> get publicResult => <String, Object?>{
    'status': 'no_op',
    'reason': reason,
  };
}

/// Authority composition for the accepted M1 bankruptcy transition.
///
/// Authentication, ingress-time eligibility and durable identity stay here.
/// Liquidation, settlement, transfers and game completion remain single-owned
/// by [BankruptcyTransitionEngine].
abstract final class AuthorityBankruptcyPlanner {
  static AuthorityBankruptcyEvaluation evaluateHuman({
    required GameCommand command,
    required String authenticatedActorUid,
    required Map<String, String> memberUidByPlayerId,
    required PublicGameState state,
    required RulesCatalog catalog,
    required DateTime requestReceivedAt,
  }) {
    if (authenticatedActorUid.isEmpty ||
        memberUidByPlayerId[command.actorPlayerId] != authenticatedActorUid) {
      throw const AuthorityBankruptcyViolation('actorNotAuthenticatedMember');
    }

    final deadlineAt = _currentDebtDeadlineAt(state);
    if (deadlineAt != null && !requestReceivedAt.toUtc().isBefore(deadlineAt)) {
      return AuthorityBankruptcyRejected(
        BankruptcyRejection(
          commandId: command.commandId,
          stateVersionBefore: state.header.stateVersion,
          errorCode: BankruptcyErrorCode.decisionClosed,
        ),
      );
    }
    return _evaluateEngine(command: command, state: state, catalog: catalog);
  }

  /// Resolves the current debt deadline with the deterministic system command
  /// identity `deadline:v1:{decisionId}`. Early and stale wakes are read-only.
  static AuthorityBankruptcyEvaluation evaluateDeadline({
    required PublicGameState state,
    required RulesCatalog catalog,
    required DateTime authorityNow,
    required String decisionId,
    required String debtCaseId,
    required String debtorPlayerId,
    required int expectedStateVersion,
  }) {
    if (state.header.stateVersion != expectedStateVersion) {
      return const AuthorityBankruptcyNoOp(reason: 'staleStateVersion');
    }
    final parsed = _parseDebtDecision(state);
    if (parsed == null ||
        parsed.decision.decisionId != decisionId ||
        parsed.debtCaseId != debtCaseId ||
        parsed.debtorPlayerId != debtorPlayerId) {
      return const AuthorityBankruptcyNoOp(reason: 'staleDecision');
    }
    final resolution = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: parsed.decision,
      decisionId: decisionId,
      authorityNow: authorityNow.toUtc(),
    );
    if (!resolution.isDue) {
      return AuthorityBankruptcyNoOp(reason: resolution.status.name);
    }
    if (resolution.action != DeadlineAction.delegateAutoLiquidation) {
      throw const AuthorityBankruptcyViolation('unsupportedDebtDeadlineAction');
    }

    return _evaluateEngine(
      command: GameCommand(
        commandId: resolution.operationId!,
        schemaVersion: state.header.schemaVersion,
        expectedStateVersion: state.header.stateVersion,
        clientInstanceId: 'authority-system',
        gameId: state.header.gameId,
        actorPlayerId: parsed.debtorPlayerId,
        type: GameCommandType.declareBankruptcy,
        payload: <String, Object?>{
          'debtCaseId': parsed.debtCaseId,
          'decisionId': decisionId,
        },
      ),
      state: state,
      catalog: catalog,
    );
  }

  static AuthorityBankruptcyEvaluation _evaluateEngine({
    required GameCommand command,
    required PublicGameState state,
    required RulesCatalog catalog,
  }) {
    final evaluation = BankruptcyTransitionEngine.evaluate(
      command: command,
      state: state,
      catalog: catalog,
    );
    if (evaluation is BankruptcyRejection) {
      return AuthorityBankruptcyRejected(evaluation);
    }
    return AuthorityBankruptcyAccepted(
      AuthorityBankruptcyPlan(evaluation as BankruptcyPlan),
    );
  }

  static Map<String, Object?> semanticMaterial(GameCommand command) =>
      <String, Object?>{
        'v': SemanticFingerprintV1.version,
        'family': 'game',
        'type': command.type.wireValue,
        'target': command.gameId,
        'expectedVersion': command.expectedStateVersion,
        'actorPlayerId': command.actorPlayerId,
        'payload': command.payload,
      };

  static String inputHash(GameCommand command) =>
      SemanticFingerprintV1.sha256Hex(semanticMaterial(command));
}

DateTime? _currentDebtDeadlineAt(PublicGameState state) {
  final pending = state.pendingDecision;
  if (pending == null || pending['kind'] != 'debtResolution') {
    return null;
  }
  final raw = pending['deadlineAt'];
  if (raw == null) return null;
  if (raw is! String) {
    throw const AuthorityBankruptcyViolation('invalidPendingDeadline');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc) {
    throw const AuthorityBankruptcyViolation('invalidPendingDeadline');
  }
  return parsed;
}

_DebtDecision? _parseDebtDecision(PublicGameState state) {
  final raw = state.pendingDecision;
  final debt = state.debtCase;
  if (raw == null || raw['kind'] != 'debtResolution' || debt == null) {
    return null;
  }
  final decisionId = raw['decisionId'];
  final stateVersionCreated = raw['stateVersionCreated'];
  final createdAt = raw['createdAt'];
  final deadlineAt = raw['deadlineAt'];
  final timeoutPolicy = raw['timeoutPolicy'];
  final allowed = raw['allowedPlayerIds'];
  final debtCaseId = debt['debtCaseId'];
  final debtorPlayerId = debt['debtorPlayerId'];
  if (decisionId is! String ||
      stateVersionCreated is! int ||
      stateVersionCreated != state.header.stateVersion ||
      createdAt is! String ||
      deadlineAt is! String ||
      (timeoutPolicy != 'declareBankruptcy' &&
          timeoutPolicy != 'autoLiquidate') ||
      allowed is! List<Object?> ||
      allowed.length != 1 ||
      allowed.single != debtorPlayerId ||
      debtCaseId is! String ||
      debtorPlayerId is! String) {
    throw const AuthorityBankruptcyViolation('invalidDebtDeadlineState');
  }
  final created = DateTime.tryParse(createdAt);
  final deadline = DateTime.tryParse(deadlineAt);
  if (created == null ||
      deadline == null ||
      !created.isUtc ||
      !deadline.isUtc) {
    throw const AuthorityBankruptcyViolation('invalidDebtDeadlineState');
  }
  return _DebtDecision(
    debtCaseId: debtCaseId,
    debtorPlayerId: debtorPlayerId,
    decision: PendingDecision(
      decisionId: decisionId,
      kind: PendingDecisionKind.debtResolution,
      allowedPlayerIds: <String>[debtorPlayerId],
      stateVersionCreated: stateVersionCreated,
      createdAt: created,
      deadlineAt: deadline,
      timeoutPolicy: TimeoutPolicy.autoLiquidate,
    ),
  );
}

final class _DebtDecision {
  const _DebtDecision({
    required this.debtCaseId,
    required this.debtorPlayerId,
    required this.decision,
  });

  final String debtCaseId;
  final String debtorPlayerId;
  final PendingDecision decision;
}
