import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_game_core/game_core.dart';

import '../buy_auction_planner.dart';
import '../ingress/command_ingress.dart';
import '../observability/authority_observability.dart';
import '../reconnect_planner.dart' as reconnect_planner;
import '../rng_operation_planner.dart';
import '../roll_movement_planner.dart';
import '../security/firebase_identity_verifier.dart';
import '../security/membership_authorizer.dart';
import 'authority_http_ingress.dart';
import 'first_playable_response_adapter.dart';

final class FirstPlayableAuthorityExecutorViolation implements Exception {
  const FirstPlayableAuthorityExecutorViolation(this.code);

  final String code;

  @override
  String toString() => 'FirstPlayableAuthorityExecutorViolation: $code';
}

/// Private receipt record loaded from the command document in the same
/// transaction as the authoritative game state.
///
/// [actorUid] never crosses the public response boundary. It prevents another
/// room member from replaying an otherwise matching command identity.
final class StoredAuthorityCommandReceipt {
  const StoredAuthorityCommandReceipt({
    required this.actorUid,
    required this.receipt,
  });

  final String actorUid;
  final reconnect_planner.DurableCommandReceipt receipt;
}

/// Typed Firestore transaction view required by the VP0 command executor.
///
/// A concrete adapter decodes Firestore documents once, then supplies the
/// canonical domain objects here. The executor never accepts client-owned game
/// state and never interprets gameplay fields itself.
final class FirstPlayableGameTransactionView {
  FirstPlayableGameTransactionView({
    required this.publicState,
    required this.catalog,
    required Map<String, String> memberUidByPlayerId,
    required this.privateRng,
    this.storedReceipt,
  }) : memberUidByPlayerId = Map.unmodifiable(memberUidByPlayerId) {
    if (publicState.header.rulesVersion != catalog.rulesVersion) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'rulesCatalogVersionMismatch',
      );
    }
    if (this.memberUidByPlayerId.entries.any(
      (entry) => entry.key.isEmpty || entry.value.isEmpty,
    )) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidMemberMapping',
      );
    }
    if (this.memberUidByPlayerId.values.toSet().length !=
        this.memberUidByPlayerId.length) {
      throw const FirstPlayableAuthorityExecutorViolation('duplicateMemberUid');
    }
  }

  final PublicGameState publicState;
  final RulesCatalog catalog;
  final Map<String, String> memberUidByPlayerId;
  final AuthorityPrivateRngSnapshot? privateRng;
  final StoredAuthorityCommandReceipt? storedReceipt;
}

/// One deterministic transaction decision returned to the Firestore adapter.
///
/// When [publicStateAfter] is present, the adapter commits it atomically with
/// [receiptToPersist] and, for Roll, [privateRngAfter]. Rejections persist only
/// their safe receipt. Duplicate/collision decisions perform zero writes.
final class FirstPlayableGameTransactionDecision {
  FirstPlayableGameTransactionDecision({
    required this.reply,
    required this.outcome,
    required this.reason,
    this.publicStateAfter,
    this.privateRngAfter,
    this.receiptToPersist,
  }) {
    final accepted = reply.status == api.AuthorityCommandStatus.accepted;
    final replay = reply.status == api.AuthorityCommandStatus.duplicate;
    if (accepted != (publicStateAfter != null) ||
        accepted && receiptToPersist == null ||
        replay &&
            (publicStateAfter != null ||
                privateRngAfter != null ||
                receiptToPersist != null) ||
        !accepted && privateRngAfter != null) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidTransactionDecision',
      );
    }
  }

  final api.AuthorityCommandReply reply;
  final AuthorityOutcome outcome;
  final AuthorityReason reason;
  final PublicGameState? publicStateAfter;
  final AuthorityPrivateRngSnapshot? privateRngAfter;
  final StoredAuthorityCommandReceipt? receiptToPersist;
}

final class FirstPlayableGameTransactionResult {
  const FirstPlayableGameTransactionResult({
    required this.decision,
    this.metrics = const AuthorityExecutionMetrics(),
  });

  final FirstPlayableGameTransactionDecision decision;
  final AuthorityExecutionMetrics metrics;
}

final class FirstPlayableGameReadResult {
  const FirstPlayableGameReadResult({
    required this.view,
    this.metrics = const AuthorityExecutionMetrics(),
  });

  final FirstPlayableGameTransactionView view;
  final AuthorityExecutionMetrics metrics;
}

typedef FirstPlayableGameTransactionCallback =
    FirstPlayableGameTransactionDecision Function(
      FirstPlayableGameTransactionView view,
    );

/// Minimal durable repository contract for the live Flutter vertical slice.
///
/// `transactGame` must load the game, optional private RNG document and command
/// receipt in one Firestore transaction; invoke [evaluate] inside its retry
/// callback; and atomically apply exactly the returned decision. Secure seed,
/// tokens and direct UID mappings must remain server-side.
abstract interface class FirstPlayableAuthorityStore {
  Future<FirstPlayableGameTransactionResult> transactGame({
    required String gameId,
    required String commandId,
    required FirstPlayableGameTransactionCallback evaluate,
  });

  /// Consistent authority read for reconnect/public snapshot replacement.
  Future<FirstPlayableGameReadResult> readGame({
    required String gameId,
    String? commandId,
  });
}

/// Concrete VP0 composition behind [AuthorityHttpIngress].
///
/// Rules remain in Engine planners. This class owns only authentication scope,
/// duplicate/collision classification, the atomic repository decision and the
/// public response mapping consumed by Flutter.
final class FirstPlayableAuthorityExecutor implements AuthorityHttpExecutor {
  const FirstPlayableAuthorityExecutor({required this._store});

  final FirstPlayableAuthorityStore _store;

  @override
  Future<AuthorityExecutionResult<api.AuthorityCommandReply>> executeCommand({
    required IngressContext context,
    required VerifiedIdentity identity,
    required api.AuthorityCommandRequest request,
  }) async {
    if (request.family != api.AuthorityCommandFamily.game) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'roomCommandCompositionPending',
      );
    }
    final command = request.asGameCommand;
    final transaction = await _store.transactGame(
      gameId: command.gameId,
      commandId: command.commandId,
      evaluate: (view) => _evaluateGameCommand(
        context: context,
        actorUid: identity.uid,
        request: request,
        command: command,
        view: view,
      ),
    );
    final decision = transaction.decision;
    return AuthorityExecutionResult<api.AuthorityCommandReply>(
      value: decision.reply,
      outcome: decision.outcome,
      reason: decision.reason,
      metrics: transaction.metrics,
    );
  }

  @override
  Future<api.AuthorityReconnectReply> reconnect({
    required IngressContext context,
    required VerifiedIdentity identity,
    required api.AuthorityReconnectRequest request,
  }) async {
    final read = await _store.readGame(
      gameId: request.gameId,
      commandId: request.uncertainCommand?.commandId,
    );
    final playerId = _requirePlayerId(read.view, identity.uid);
    final uncertain = request.uncertainCommand;
    final stored = read.view.storedReceipt;
    final durableReceipt = stored == null
        ? null
        : stored.actorUid == identity.uid
        ? stored.receipt
        : reconnect_planner.DurableCommandReceipt(
            commandId: stored.receipt.commandId,
            inputHashVersion: stored.receipt.inputHashVersion,
            inputHash: List<String>.filled(64, '0').join(),
            publicResult: stored.receipt.publicResult,
          );
    final plan = reconnect_planner.AuthorityReconnectPlanner.reconcile(
      authenticatedActorUid: identity.uid,
      actorPlayerId: playerId,
      memberUidByPlayerId: read.view.memberUidByPlayerId,
      clientStateVersion: request.observedStateVersion,
      authoritativeState: read.view.publicState,
      uncertainCommand: uncertain == null
          ? null
          : reconnect_planner.UncertainCommandIdentity(
              commandId: uncertain.commandId,
              inputHashVersion: uncertain.inputHashVersion,
              inputHash: uncertain.inputHash,
            ),
      durableReceipt: durableReceipt,
    );
    return FirstPlayableResponseAdapter.reconnect(plan: plan, request: request);
  }

  @override
  Future<api.AuthorityPublicSnapshot> readPublicGame({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String gameId,
  }) async {
    final read = await _store.readGame(gameId: gameId);
    _requirePlayerId(read.view, identity.uid);
    return api.AuthorityPublicSnapshot(read.view.publicState.toJson());
  }

  static FirstPlayableGameTransactionDecision _evaluateGameCommand({
    required IngressContext context,
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required GameCommand command,
    required FirstPlayableGameTransactionView view,
  }) {
    final prior = view.storedReceipt;
    if (prior != null) {
      final exactDuplicate =
          prior.actorUid == actorUid &&
          prior.receipt.commandId == command.commandId &&
          prior.receipt.inputHashVersion == request.inputHashVersion &&
          prior.receipt.inputHash == request.inputHash;
      if (exactDuplicate) {
        return FirstPlayableGameTransactionDecision(
          reply: FirstPlayableResponseAdapter.duplicate(prior.receipt),
          outcome: AuthorityOutcome.duplicate,
          reason: AuthorityReason.duplicateCommand,
        );
      }
      final version = view.publicState.header.stateVersion;
      return FirstPlayableGameTransactionDecision(
        reply: api.AuthorityCommandReply(
          commandId: command.commandId,
          status: api.AuthorityCommandStatus.rejected,
          versionBefore: version,
          versionAfter: version,
          errorCode: 'commandIdCollision',
          publicResult: <String, Object?>{
            'commandId': command.commandId,
            'status': 'rejected',
            'stateVersionBefore': version,
            'stateVersionAfter': version,
            'errorCode': 'commandIdCollision',
          },
        ),
        outcome: AuthorityOutcome.collision,
        reason: AuthorityReason.commandIdCollision,
      );
    }

    final evaluation = switch (command.type) {
      GameCommandType.rollDice => _evaluateRoll(
        context: context,
        actorUid: actorUid,
        command: command,
        view: view,
      ),
      GameCommandType.buyProperty ||
      GameCommandType.declineProperty ||
      GameCommandType.placeBid ||
      GameCommandType.passAuction => _evaluateBuyAuction(
        context: context,
        actorUid: actorUid,
        command: command,
        view: view,
      ),
      _ => throw FirstPlayableAuthorityExecutorViolation(
        'unsupportedGameCommand:${command.type.wireValue}',
      ),
    };
    return _persistableDecision(
      actorUid: actorUid,
      request: request,
      evaluation: evaluation,
    );
  }

  static _EvaluatedGameCommand _evaluateRoll({
    required IngressContext context,
    required String actorUid,
    required GameCommand command,
    required FirstPlayableGameTransactionView view,
  }) {
    final privateRng = view.privateRng;
    if (privateRng == null) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'privateRngUnavailable',
      );
    }
    final evaluation = AuthorityRollMovementPlanner.evaluate(
      command: command,
      authenticatedActorUid: actorUid,
      memberUidByPlayerId: view.memberUidByPlayerId,
      state: view.publicState,
      catalog: view.catalog,
      privateSnapshot: privateRng,
      transitionTime: context.requestReceivedAt,
    );
    final reply = FirstPlayableResponseAdapter.rollMovement(evaluation);
    return switch (evaluation) {
      AuthorityRollMovementAccepted(:final plan) => _EvaluatedGameCommand(
        reply: reply,
        publicStateAfter: plan.stateAfter,
        privateRngAfter: plan.successorPrivateState,
      ),
      AuthorityRollMovementRejected() => _EvaluatedGameCommand(reply: reply),
    };
  }

  static _EvaluatedGameCommand _evaluateBuyAuction({
    required IngressContext context,
    required String actorUid,
    required GameCommand command,
    required FirstPlayableGameTransactionView view,
  }) {
    final evaluation = AuthorityBuyAuctionPlanner.evaluateHuman(
      command: command,
      authenticatedActorUid: actorUid,
      memberUidByPlayerId: view.memberUidByPlayerId,
      state: view.publicState,
      catalog: view.catalog,
      requestReceivedAt: context.requestReceivedAt,
    );
    final reply = FirstPlayableResponseAdapter.buyAuction(evaluation);
    return switch (evaluation) {
      AuthorityBuyAuctionAccepted(:final plan) => _EvaluatedGameCommand(
        reply: reply,
        publicStateAfter: plan.stateAfter,
      ),
      AuthorityBuyAuctionRejected() => _EvaluatedGameCommand(reply: reply),
      AuthorityBuyAuctionNoOp() =>
        throw const FirstPlayableAuthorityExecutorViolation(
          'unexpectedHumanNoOp',
        ),
    };
  }

  static FirstPlayableGameTransactionDecision _persistableDecision({
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required _EvaluatedGameCommand evaluation,
  }) {
    final reply = evaluation.reply;
    final receipt = StoredAuthorityCommandReceipt(
      actorUid: actorUid,
      receipt: reconnect_planner.DurableCommandReceipt(
        commandId: reply.commandId,
        inputHashVersion: request.inputHashVersion,
        inputHash: request.inputHash,
        publicResult: reply.publicResult,
      ),
    );
    final reason = switch (reply.errorCode) {
      'staleVersion' => AuthorityReason.staleVersion,
      'decisionClosed' => AuthorityReason.decisionClosed,
      _ => AuthorityReason.none,
    };
    return FirstPlayableGameTransactionDecision(
      reply: reply,
      outcome: reply.status == api.AuthorityCommandStatus.accepted
          ? AuthorityOutcome.success
          : reason == AuthorityReason.staleVersion
          ? AuthorityOutcome.stale
          : AuthorityOutcome.rejected,
      reason: reason,
      publicStateAfter: evaluation.publicStateAfter,
      privateRngAfter: evaluation.privateRngAfter,
      receiptToPersist: receipt,
    );
  }

  static String _requirePlayerId(
    FirstPlayableGameTransactionView view,
    String actorUid,
  ) {
    final matches = view.memberUidByPlayerId.entries
        .where((entry) => entry.value == actorUid)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (matches.length != 1) {
      throw const MembershipAuthorizationException('not_a_member');
    }
    return matches.single;
  }
}

final class _EvaluatedGameCommand {
  const _EvaluatedGameCommand({
    required this.reply,
    this.publicStateAfter,
    this.privateRngAfter,
  });

  final api.AuthorityCommandReply reply;
  final PublicGameState? publicStateAfter;
  final AuthorityPrivateRngSnapshot? privateRngAfter;
}
