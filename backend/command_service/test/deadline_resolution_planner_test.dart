import 'dart:convert';
import 'dart:io';

import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  final vectors = (jsonDecode(
    File('test/fixtures/deadline_engine_plans.json').readAsStringSync(),
  ) as List<dynamic>).cast<Map<String, dynamic>>();

  for (final vector in vectors) {
    test('shared durable vector ${vector['id']} is produced by Engine', () {
      final decision = PendingDecision(
        decisionId: vector['decisionId'] as String,
        kind: PendingDecisionKind.values.byName(vector['kind'] as String),
        allowedPlayerIds: const ['player-1'],
        stateVersionCreated: vector['stateVersionCreated'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          vector['createdAtMs'] as int,
          isUtc: true,
        ),
        deadlineAt: DateTime.fromMillisecondsSinceEpoch(
          vector['deadlineAtMs'] as int,
          isUtc: true,
        ),
        timeoutPolicy: TimeoutPolicy.values.byName(vector['policy'] as String),
      );

      final plan = DeadlineResolutionPlanner.plan(
        currentDecision: decision,
        decisionId: decision.decisionId,
        authorityNow: DateTime.fromMillisecondsSinceEpoch(
          vector['authorityNowMs'] as int,
          isUtc: true,
        ),
      );

      expect(plan.decisionId, vector['decisionId']);
      expect(plan.expectedStateVersion, vector['stateVersionCreated']);
      expect(plan.dispositionWireName, vector['expectedDisposition']);
      expect(plan.actionWireName, vector['expectedAction']);
      expect(plan.operationId, vector['expectedOperationId']);
    });
  }

  test('early wake produces no persistence operation', () {
    final decision = PendingDecision(
      decisionId: 'early-decision',
      kind: PendingDecisionKind.auctionTurn,
      allowedPlayerIds: const ['player-1'],
      stateVersionCreated: 5,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      deadlineAt: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
      timeoutPolicy: TimeoutPolicy.pass,
    );

    final plan = DeadlineResolutionPlanner.plan(
      currentDecision: decision,
      decisionId: decision.decisionId,
      authorityNow: DateTime.fromMillisecondsSinceEpoch(4999, isUtc: true),
    );

    expect(plan.disposition, DeadlinePlanDisposition.noOp);
    expect(plan.action, DeadlineAction.none);
    expect(plan.reason, 'notDue');
    expect(plan.operationId, isNull);
  });

  test('stale decision produces no persistence operation', () {
    final decision = PendingDecision(
      decisionId: 'current-decision',
      kind: PendingDecisionKind.tradeResponse,
      allowedPlayerIds: const ['player-1'],
      stateVersionCreated: 9,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      deadlineAt: DateTime.fromMillisecondsSinceEpoch(5000, isUtc: true),
      timeoutPolicy: TimeoutPolicy.reject,
    );

    final plan = DeadlineResolutionPlanner.plan(
      currentDecision: decision,
      decisionId: 'stale-decision',
      authorityNow: DateTime.fromMillisecondsSinceEpoch(6000, isUtc: true),
    );

    expect(plan.disposition, DeadlinePlanDisposition.noOp);
    expect(plan.action, DeadlineAction.none);
    expect(plan.reason, 'staleDecision');
    expect(plan.operationId, isNull);
  });
}
