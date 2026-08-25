import 'package:board_backend_api/backend_api.dart';
import 'package:board_game_core/game_core.dart';

final class AuthorityBuyAuctionViolation implements Exception {
  const AuthorityBuyAuctionViolation(this.code);

  final String code;

  @override
  String toString() => 'AuthorityBuyAuctionViolation: $code';
}

/// Atomic persistence plan produced from the canonical Engine evaluation.
///
/// The durable adapter commits [stateAfter] and [safeResultSummary] together.
/// Buy/Auction does not mutate private RNG state; an adapter must leave the
/// existing `gameSecrets` document byte-for-byte unchanged.
final class AuthorityBuyAuctionPlan {
  const AuthorityBuyAuctionPlan(this.enginePlan);

  final BuyAuctionPlan enginePlan;

  PublicGameState get stateAfter => enginePlan.stateAfter;

  Map<String, Object?> get safeResultSummary => <String, Object?>{
    'commandId': enginePlan.commandId,
    'status': 'accepted',
    'stateVersionBefore': enginePlan.stateVersionBefore,
    'stateVersionAfter': enginePlan.stateVersionAfter,
    'events': enginePlan.events
        .map((event) => event.toJson())
        .toList(growable: false),
  };
}

sealed class AuthorityBuyAuctionEvaluation {
  const AuthorityBuyAuctionEvaluation();

  bool get accepted;
  Map<String, Object?> get publicResult;
}

final class AuthorityBuyAuctionAccepted extends AuthorityBuyAuctionEvaluation {
  const AuthorityBuyAuctionAccepted(this.plan);

  final AuthorityBuyAuctionPlan plan;

  @override
  bool get accepted => true;

  @override
  Map<String, Object?> get publicResult => plan.safeResultSummary;
}

final class AuthorityBuyAuctionRejected extends AuthorityBuyAuctionEvaluation {
  const AuthorityBuyAuctionRejected(this.rejection);

  final BuyAuctionRejection rejection;

  @override
  bool get accepted => false;

  @override
  Map<String, Object?> get publicResult => rejection.toPublicJson();
}

final class AuthorityBuyAuctionNoOp extends AuthorityBuyAuctionEvaluation {
  const AuthorityBuyAuctionNoOp({required this.reason});

  final String reason;

  @override
  bool get accepted => false;

  @override
  Map<String, Object?> get publicResult => <String, Object?>{
    'status': 'no_op',
    'reason': reason,
  };
}

/// Authority composition for the controlled VP0 Buy/Decline/Auction slice.
///
/// Membership, ingress-time deadline eligibility, command identity and
/// persistence stay here. Cash, ownership, bidder rotation, bid validation and
/// auction completion remain single-owned by [BuyAuctionEngine].
abstract final class AuthorityBuyAuctionPlanner {
  static AuthorityBuyAuctionEvaluation evaluateHuman({
    required GameCommand command,
    required String authenticatedActorUid,
    required Map<String, String> memberUidByPlayerId,
    required PublicGameState state,
    required RulesCatalog catalog,
    required DateTime requestReceivedAt,
  }) {
    if (authenticatedActorUid.isEmpty ||
        memberUidByPlayerId[command.actorPlayerId] != authenticatedActorUid) {
      throw const AuthorityBuyAuctionViolation('actorNotAuthenticatedMember');
    }

    final deadlineAt = _currentDeadlineAt(state);
    if (deadlineAt != null && !requestReceivedAt.toUtc().isBefore(deadlineAt)) {
      return AuthorityBuyAuctionRejected(
        BuyAuctionRejection(
          commandId: command.commandId,
          stateVersionBefore: state.header.stateVersion,
          errorCode: BuyAuctionErrorCode.decisionClosed,
        ),
      );
    }

    return _evaluateEngine(
      command: command,
      state: state,
      catalog: catalog,
      transitionTime: requestReceivedAt,
    );
  }

  /// Materializes an auction timeout through the accepted deadline contract.
  ///
  /// The deterministic `deadline:v1:{decisionId}` identity is also the system
  /// commandId. Early/stale wakes are read-only. A due `pass` is delegated back
  /// to [BuyAuctionEngine], so Authority never reimplements bidder rotation or
  /// winner/payment/ownership semantics.
  static AuthorityBuyAuctionEvaluation evaluateAuctionDeadline({
    required PublicGameState state,
    required RulesCatalog catalog,
    required DateTime authorityNow,
  }) {
    final parsed = _parseAuctionDecision(state);
    if (parsed == null) {
      return const AuthorityBuyAuctionNoOp(reason: 'staleDecision');
    }
    final resolution = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: parsed.decision,
      decisionId: parsed.decision.decisionId,
      authorityNow: authorityNow.toUtc(),
    );
    if (!resolution.isDue) {
      return AuthorityBuyAuctionNoOp(reason: resolution.status.name);
    }
    if (!resolution.isTerminal || resolution.action != DeadlineAction.pass) {
      throw const AuthorityBuyAuctionViolation(
        'unsupportedAuctionDeadlineAction',
      );
    }

    return _evaluateEngine(
      command: GameCommand(
        commandId: resolution.operationId!,
        schemaVersion: state.header.schemaVersion,
        expectedStateVersion: state.header.stateVersion,
        clientInstanceId: 'authority-system',
        gameId: state.header.gameId,
        actorPlayerId: parsed.actorPlayerId,
        type: GameCommandType.passAuction,
        payload: <String, Object?>{'auctionId': parsed.auctionId},
      ),
      state: state,
      catalog: catalog,
      transitionTime: authorityNow,
    );
  }

  static AuthorityBuyAuctionEvaluation _evaluateEngine({
    required GameCommand command,
    required PublicGameState state,
    required RulesCatalog catalog,
    required DateTime transitionTime,
  }) {
    final evaluation = BuyAuctionEngine.evaluate(
      command: command,
      state: state,
      catalog: catalog,
      transitionTime: transitionTime.toUtc(),
    );
    if (evaluation is BuyAuctionRejection) {
      return AuthorityBuyAuctionRejected(evaluation);
    }
    return AuthorityBuyAuctionAccepted(
      AuthorityBuyAuctionPlan(evaluation as BuyAuctionPlan),
    );
  }

  /// Semantic material used before Engine invocation to distinguish a safe
  /// duplicate from a commandId collision.
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

DateTime? _currentDeadlineAt(PublicGameState state) {
  final raw = state.pendingDecision?['deadlineAt'];
  if (raw == null) {
    return null;
  }
  if (raw is! String) {
    throw const AuthorityBuyAuctionViolation('invalidPendingDeadline');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || !parsed.isUtc) {
    throw const AuthorityBuyAuctionViolation('invalidPendingDeadline');
  }
  return parsed;
}

_AuctionDecision? _parseAuctionDecision(PublicGameState state) {
  final raw = state.pendingDecision;
  if (raw == null || raw['kind'] != 'auctionTurn') {
    return null;
  }
  final decisionId = raw['decisionId'];
  final stateVersionCreated = raw['stateVersionCreated'];
  final createdAt = raw['createdAt'];
  final deadlineAt = raw['deadlineAt'];
  final timeoutPolicy = raw['timeoutPolicy'];
  final allowed = raw['allowedPlayerIds'];
  final payload = raw['payload'];
  if (decisionId is! String ||
      stateVersionCreated is! int ||
      createdAt is! String ||
      deadlineAt is! String ||
      timeoutPolicy != 'pass' ||
      allowed is! List<Object?> ||
      allowed.length != 1 ||
      allowed.single is! String ||
      payload is! Map<String, Object?> ||
      payload['auctionId'] is! String) {
    throw const AuthorityBuyAuctionViolation('invalidAuctionDeadlineState');
  }
  final created = DateTime.tryParse(createdAt);
  final deadline = DateTime.tryParse(deadlineAt);
  if (created == null ||
      deadline == null ||
      !created.isUtc ||
      !deadline.isUtc) {
    throw const AuthorityBuyAuctionViolation('invalidAuctionDeadlineState');
  }
  final actorPlayerId = allowed.single! as String;
  return _AuctionDecision(
    actorPlayerId: actorPlayerId,
    auctionId: payload['auctionId']! as String,
    decision: PendingDecision(
      decisionId: decisionId,
      kind: PendingDecisionKind.auctionTurn,
      allowedPlayerIds: <String>[actorPlayerId],
      stateVersionCreated: stateVersionCreated,
      createdAt: created,
      deadlineAt: deadline,
      timeoutPolicy: TimeoutPolicy.pass,
    ),
  );
}

final class _AuctionDecision {
  const _AuctionDecision({
    required this.actorPlayerId,
    required this.auctionId,
    required this.decision,
  });

  final String actorPlayerId;
  final String auctionId;
  final PendingDecision decision;
}
