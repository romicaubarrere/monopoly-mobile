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
    String? receiptActorUid = 'uid-p1',
  }) => AuthorityReconnectPlanner.reconcile(
    authenticatedActorUid: 'uid-p1',
    actorPlayerId: 'p1',
    memberUidByPlayerId: memberUidByPlayerId,
    clientStateVersion: clientStateVersion,
    authoritativeState: state,
    uncertainCommand: command,
    durableReceipt: receipt,
    durableReceiptActorUid: receipt == null ? null : receiptActorUid,
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
        durableReceiptActorUid: null,
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

  for (final status in ['accepted', 'rejected']) {
    for (final hashDigit in ['0', 'a']) {
      for (final ownsReceipt in [false, true]) {
        test('$status hash $hashDigit ownership $ownsReceipt is explicit', () {
          final hash = List<String>.filled(64, hashDigit).join();
          final identity = UncertainCommandIdentity(
            commandId: uncertain.commandId,
            inputHashVersion: 1,
            inputHash: hash,
          );
          final result = <String, Object?>{
            'commandId': identity.commandId,
            'status': status,
            'stateVersionBefore': 0,
            'stateVersionAfter': 1,
            if (status == 'rejected') 'errorCode': 'staleVersion',
          };
          final receipt = DurableCommandReceipt(
            commandId: identity.commandId,
            inputHashVersion: 1,
            inputHash: hash,
            publicResult: result,
          );
          final before = state.toJson();
          final plan = reconcile(
            command: identity,
            receipt: receipt,
            receiptActorUid: ownsReceipt ? 'uid-p1' : 'uid-p2',
          );
          expect(plan.authoritativeState, same(state));
          expect(state.toJson(), before);
          expect(receipt.inputHash, hash);
          expect(receipt.publicResult, same(result));
          final resolution = plan.commandResolution!;
          expect(resolution['commandId'], identity.commandId);
          expect(resolution['inputHashVersion'], 1);
          if (ownsReceipt) {
            expect(
              plan.disposition,
              status == 'accepted'
                  ? ReconnectDisposition.uncertainConfirmed
                  : ReconnectDisposition.uncertainRejected,
            );
            expect(resolution['action'], 'useDurableResult');
            expect(resolution['result'], result);
          } else {
            expect(plan.disposition, ReconnectDisposition.semanticCollision);
            expect(resolution['action'], 'failClosed');
            expect(resolution['errorCode'], 'commandIdCollision');
            expect(resolution, isNot(contains('result')));
            expect(plan.toCanonicalPublicJson(), isNot(contains('uid-p2')));
          }
        });
      }
    }
  }

  final receipt = DurableCommandReceipt(
    commandId: uncertain.commandId,
    inputHashVersion: 1,
    inputHash: uncertain.inputHash,
    publicResult: const <String, Object?>{'status': 'accepted'},
  );
  for (final binding in [
    (name: 'missing owner', receipt: receipt, owner: null),
    (name: 'empty owner', receipt: receipt, owner: ''),
    (name: 'orphan owner', receipt: null, owner: 'uid-p1'),
    (name: 'orphan empty owner', receipt: null, owner: ''),
  ]) {
    test('receipt binding rejects ${binding.name}', () {
      expect(
        () => AuthorityReconnectPlanner.reconcile(
          authenticatedActorUid: 'uid-p1',
          actorPlayerId: 'p1',
          memberUidByPlayerId: memberUidByPlayerId,
          clientStateVersion: 0,
          authoritativeState: state,
          uncertainCommand: uncertain,
          durableReceipt: binding.receipt,
          durableReceiptActorUid: binding.owner,
        ),
        throwsA(
          isA<AuthorityReconnectViolation>().having(
            (error) => error.code,
            'code',
            'invalidDurableReceiptActor',
          ),
        ),
      );
    });
  }

  test('client-ahead validation precedes receipt owner collision', () {
    expect(
      () => reconcile(
        clientStateVersion: 2,
        command: uncertain,
        receipt: receipt,
        receiptActorUid: 'uid-p2',
      ),
      throwsA(
        isA<AuthorityReconnectViolation>().having(
          (error) => error.code,
          'code',
          'clientVersionAheadOfAuthority',
        ),
      ),
    );
  });

  test('orphan receipt validation remains before ownership classification', () {
    expect(
      () => reconcile(receipt: receipt, receiptActorUid: 'uid-p2'),
      throwsA(
        isA<AuthorityReconnectViolation>().having(
          (error) => error.code,
          'code',
          'orphanDurableReceipt',
        ),
      ),
    );
  });
}
