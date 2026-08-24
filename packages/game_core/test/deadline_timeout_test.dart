import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 24, 2);
  final deadlineAt = createdAt.add(const Duration(seconds: 20));

  PendingDecision decision({
    String id = 'decision-1',
    PendingDecisionKind kind = PendingDecisionKind.auctionTurn,
    TimeoutPolicy policy = TimeoutPolicy.pass,
    DateTime? deadline,
  }) => PendingDecision(
    decisionId: id,
    kind: kind,
    allowedPlayerIds: const ['player-1'],
    stateVersionCreated: 10,
    createdAt: createdAt,
    deadlineAt: deadline ?? deadlineAt,
    timeoutPolicy: policy,
  );

  test('deadline_before_expiry_is_noop', () {
    final result = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: decision(),
      decisionId: 'decision-1',
      authorityNow: deadlineAt.subtract(const Duration(milliseconds: 1)),
    );

    expect(result.status, DeadlineResolutionStatus.notDue);
    expect(result.action, DeadlineAction.none);
    expect(result.operationId, isNull);
  });

  test('deadline_boundary_is_inclusive_and_identity_is_deterministic', () {
    final result = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: decision(),
      decisionId: 'decision-1',
      authorityNow: deadlineAt,
    );

    expect(result.status, DeadlineResolutionStatus.ready);
    expect(result.action, DeadlineAction.pass);
    expect(result.operationId, 'deadline:v1:decision-1');
    expect(
      DeadlineTimeoutEngine.operationIdFor('decision-1'),
      'deadline:v1:decision-1',
    );
  });

  test('stale_decision_is_rejected_without_timeout_effect', () {
    final result = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: decision(),
      decisionId: 'older-decision',
      authorityNow: deadlineAt.add(const Duration(seconds: 1)),
    );

    expect(result.status, DeadlineResolutionStatus.staleDecision);
    expect(result.action, DeadlineAction.none);
    expect(result.operationId, isNull);
  });

  test('decision_without_deadline_never_materializes_timeout', () {
    final noDeadline = PendingDecision(
      decisionId: 'decision-no-deadline',
      kind: PendingDecisionKind.cardChoice,
      allowedPlayerIds: const ['player-1'],
      stateVersionCreated: 10,
      createdAt: createdAt,
      timeoutPolicy: TimeoutPolicy.none,
    );

    final result = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: noDeadline,
      decisionId: noDeadline.decisionId,
      authorityNow: deadlineAt.add(const Duration(days: 1)),
    );

    expect(result.status, DeadlineResolutionStatus.noDeadline);
    expect(result.action, DeadlineAction.none);
  });

  test('auction_pass_is_terminal_and_clears_pending_decision', () {
    final current = decision();
    final result = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: current,
      decisionId: current.decisionId,
      authorityNow: deadlineAt,
    );

    expect(result.isTerminal, isTrue);
    expect(
      DeadlineTimeoutEngine.applyTerminalOutcome(
        currentDecision: current,
        resolution: result,
      ),
      isNull,
    );
  });

  test('trade_reject_is_terminal_and_clears_pending_decision', () {
    final current = decision(
      id: 'trade-1',
      kind: PendingDecisionKind.tradeResponse,
      policy: TimeoutPolicy.reject,
    );
    final result = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: current,
      decisionId: current.decisionId,
      authorityNow: deadlineAt.add(const Duration(seconds: 1)),
    );

    expect(result.action, DeadlineAction.reject);
    expect(result.isTerminal, isTrue);
    expect(
      DeadlineTimeoutEngine.applyTerminalOutcome(
        currentDecision: current,
        resolution: result,
      ),
      isNull,
    );
  });

  test('bot_decide_is_explicit_delegation_not_silent_resolution', () {
    final current = decision(
      id: 'property-1',
      kind: PendingDecisionKind.propertyOffer,
      policy: TimeoutPolicy.botDecide,
    );
    final result = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: current,
      decisionId: current.decisionId,
      authorityNow: deadlineAt,
    );

    expect(result.action, DeadlineAction.delegateBotDecision);
    expect(result.isDue, isTrue);
    expect(result.isTerminal, isFalse);
    expect(
      DeadlineTimeoutEngine.applyTerminalOutcome(
        currentDecision: current,
        resolution: result,
      ),
      same(current),
    );
  });

  test('auto_liquidate_is_explicit_delegation_not_silent_resolution', () {
    final current = decision(
      id: 'debt-1',
      kind: PendingDecisionKind.debtResolution,
      policy: TimeoutPolicy.autoLiquidate,
    );
    final result = DeadlineTimeoutEngine.resolveCurrent(
      currentDecision: current,
      decisionId: current.decisionId,
      authorityNow: deadlineAt,
    );

    expect(result.action, DeadlineAction.delegateAutoLiquidation);
    expect(result.isDue, isTrue);
    expect(result.isTerminal, isFalse);
    expect(
      DeadlineTimeoutEngine.applyTerminalOutcome(
        currentDecision: current,
        resolution: result,
      ),
      same(current),
    );
  });

  test('constructor_rejects_invalid_identity_and_state_version', () {
    expect(
      () => PendingDecision(
        decisionId: '',
        kind: PendingDecisionKind.cuchaExit,
        allowedPlayerIds: const ['player-1'],
        stateVersionCreated: 0,
        createdAt: createdAt,
        deadlineAt: deadlineAt,
        timeoutPolicy: TimeoutPolicy.botDecide,
      ),
      throwsArgumentError,
    );

    expect(
      () => PendingDecision(
        decisionId: 'decision-negative-version',
        kind: PendingDecisionKind.cuchaExit,
        allowedPlayerIds: const ['player-1'],
        stateVersionCreated: -1,
        createdAt: createdAt,
        deadlineAt: deadlineAt,
        timeoutPolicy: TimeoutPolicy.botDecide,
      ),
      throwsArgumentError,
    );
  });
}
