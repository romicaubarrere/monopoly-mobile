import 'package:board_command_service/command_service.dart';
import 'package:test/test.dart';

import 'support/synthetic_buy_auction_fixture.dart';

void main() {
  const memberUidByPlayerId = <String, String>{'p1': 'uid-p1'};
  final state = syntheticPropertyOfferState();
  final uncertain = UncertainCommandIdentity(
    commandId: 'cmd-buy-1',
    inputHashVersion: 1,
    inputHash: List<String>.filled(64, 'a').join(),
  );

  AuthorityReconnectPlan reconcile({
    int clientStateVersion = 0,
    UncertainCommandIdentity? command,
    DurableCommandReceipt? receipt,
  }) => AuthorityReconnectPlanner.reconcile(
    authenticatedActorUid: 'uid-p1',
    actorPlayerId: 'p1',
    memberUidByPlayerId: memberUidByPlayerId,
    clientStateVersion: clientStateVersion,
    authoritativeState: state,
    uncertainCommand: command,
    durableReceipt: receipt,
  );

  test('older client receives the complete authoritative public snapshot', () {
    final plan = reconcile();

    expect(plan.disposition, ReconnectDisposition.snapshotAdvanced);
    expect(plan.toPublicJson()['stateVersion'], 1);
    expect(plan.toPublicJson()['snapshot'], state.toJson());
    expect(plan.toCanonicalPublicJson(), isNot(contains('seed')));
    expect(plan.toCanonicalPublicJson(), isNot(contains('streamCounters')));
  });

  test('equal version is explicitly current without client-side merge', () {
    final plan = reconcile(clientStateVersion: 1);

    expect(plan.disposition, ReconnectDisposition.upToDate);
    expect(plan.commandResolution, isNull);
  });

  test('lost ACK resolves from the matching durable accepted result', () {
    final plan = reconcile(
      command: uncertain,
      receipt: DurableCommandReceipt(
        commandId: uncertain.commandId,
        inputHashVersion: 1,
        inputHash: uncertain.inputHash,
        publicResult: const <String, Object?>{
          'commandId': 'cmd-buy-1',
          'status': 'accepted',
          'stateVersionBefore': 1,
          'stateVersionAfter': 2,
        },
      ),
    );

    expect(plan.disposition, ReconnectDisposition.uncertainConfirmed);
    expect(plan.commandResolution!['action'], 'useDurableResult');
  });

  test('durable rejection resolves uncertainty without a new mutation', () {
    final plan = reconcile(
      command: uncertain,
      receipt: DurableCommandReceipt(
        commandId: uncertain.commandId,
        inputHashVersion: 1,
        inputHash: uncertain.inputHash,
        publicResult: const <String, Object?>{
          'commandId': 'cmd-buy-1',
          'status': 'rejected',
          'errorCode': 'staleVersion',
          'stateVersionBefore': 2,
          'stateVersionAfter': 2,
        },
      ),
    );

    expect(plan.disposition, ReconnectDisposition.uncertainRejected);
  });

  test('missing receipt requires retry of exactly the same identity', () {
    final plan = reconcile(command: uncertain);

    expect(plan.disposition, ReconnectDisposition.retrySameCommand);
    expect(plan.commandResolution, <String, Object?>{
      'commandId': 'cmd-buy-1',
      'inputHashVersion': 1,
      'action': 'retrySameCommand',
    });
  });

  test('fingerprint mismatch fails closed as semantic collision', () {
    final plan = reconcile(
      command: uncertain,
      receipt: DurableCommandReceipt(
        commandId: uncertain.commandId,
        inputHashVersion: 1,
        inputHash: List<String>.filled(64, 'b').join(),
        publicResult: const <String, Object?>{
          'commandId': 'cmd-buy-1',
          'status': 'accepted',
        },
      ),
    );

    expect(plan.disposition, ReconnectDisposition.semanticCollision);
    expect(plan.commandResolution!['errorCode'], 'commandIdCollision');
  });

  test('non-member and impossible client-ahead versions fail closed', () {
    expect(
      () => AuthorityReconnectPlanner.reconcile(
        authenticatedActorUid: 'uid-other',
        actorPlayerId: 'p1',
        memberUidByPlayerId: memberUidByPlayerId,
        clientStateVersion: 0,
        authoritativeState: state,
      ),
      throwsA(
        isA<AuthorityReconnectViolation>().having(
          (error) => error.code,
          'code',
          'actorNotAuthenticatedMember',
        ),
      ),
    );
    expect(
      () => reconcile(clientStateVersion: 2),
      throwsA(
        isA<AuthorityReconnectViolation>().having(
          (error) => error.code,
          'code',
          'clientVersionAheadOfAuthority',
        ),
      ),
    );
  });

  test('deadline bytes are preserved exactly across reconciliation', () {
    final before = state.pendingDecision!['deadlineAt'];
    final plan = reconcile();
    final snapshot = plan.toPublicJson()['snapshot']! as Map<String, Object?>;
    final pending = snapshot['pendingDecision']! as Map<String, Object?>;

    expect(pending['deadlineAt'], before);
  });
}
