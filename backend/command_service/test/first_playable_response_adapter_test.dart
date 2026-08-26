import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart' as service;
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_buy_auction_fixture.dart';
import 'support/synthetic_roll_fixture.dart';

void main() {
  final state = syntheticPropertyOfferState();
  final identity = api.UncertainCommandIdentity(
    commandId: 'cmd-buy-1',
    inputHashVersion: 1,
    inputHash: List<String>.filled(64, 'a').join(),
  );
  final request = api.AuthorityReconnectRequest(
    gameId: state.header.gameId,
    observedStateVersion: 0,
    uncertainCommand: identity,
  );

  service.AuthorityReconnectPlan plan({
    required service.UncertainCommandIdentity? uncertain,
    service.DurableCommandReceipt? receipt,
  }) => service.AuthorityReconnectPlanner.reconcile(
    authenticatedActorUid: 'uid-p1',
    actorPlayerId: 'p1',
    memberUidByPlayerId: const <String, String>{'p1': 'uid-p1'},
    clientStateVersion: 0,
    authoritativeState: state,
    uncertainCommand: uncertain,
    durableReceipt: receipt,
  );

  service.UncertainCommandIdentity plannerIdentity({String? inputHash}) =>
      service.UncertainCommandIdentity(
        commandId: identity.commandId,
        inputHashVersion: identity.inputHashVersion,
        inputHash: inputHash ?? identity.inputHash,
      );

  test('retry preserves the complete lost-ACK identity for Flutter', () {
    final reply = service.FirstPlayableResponseAdapter.reconnect(
      plan: plan(uncertain: plannerIdentity()),
      request: request,
    );

    expect(reply.disposition, api.ReconnectDisposition.retrySameCommand);
    expect(reply.commandResolution!.identity.toWireJson(), <String, Object?>{
      'commandId': 'cmd-buy-1',
      'inputHashVersion': 1,
      'inputHash': identity.inputHash,
    });
    expect(
      reply.commandResolution!.action,
      api.CommandResolutionAction.retrySameCommand,
    );
    expect(reply.toWireJson(), isNot(containsPair('status', anything)));
  });

  test('durable receipt round-trips through the Flutter wire client', () async {
    final durableResult = <String, Object?>{
      'commandId': 'cmd-buy-1',
      'status': 'accepted',
      'stateVersionBefore': 1,
      'stateVersionAfter': 2,
    };
    final reply = service.FirstPlayableResponseAdapter.reconnect(
      plan: plan(
        uncertain: plannerIdentity(),
        receipt: service.DurableCommandReceipt(
          commandId: identity.commandId,
          inputHashVersion: identity.inputHashVersion,
          inputHash: identity.inputHash,
          publicResult: durableResult,
        ),
      ),
      request: request,
    );

    final decoded = await api.WireAuthorityClient(
      _ReconnectTransport(reply.toWireJson()),
    ).reconnect(request);

    expect(decoded.disposition, api.ReconnectDisposition.uncertainConfirmed);
    expect(
      decoded.commandResolution!.action,
      api.CommandResolutionAction.useDurableResult,
    );
    expect(decoded.commandResolution!.publicResult, durableResult);
    expect(decoded.snapshot.toWireJson(), state.toJson());
  });

  test('semantic collision maps to a safe fail-closed response', () {
    final reply = service.FirstPlayableResponseAdapter.reconnect(
      plan: plan(
        uncertain: plannerIdentity(),
        receipt: service.DurableCommandReceipt(
          commandId: identity.commandId,
          inputHashVersion: identity.inputHashVersion,
          inputHash: List<String>.filled(64, 'b').join(),
          publicResult: const <String, Object?>{'status': 'accepted'},
        ),
      ),
      request: request,
    );

    expect(reply.disposition, api.ReconnectDisposition.semanticCollision);
    expect(
      reply.commandResolution!.action,
      api.CommandResolutionAction.failClosed,
    );
    expect(reply.commandResolution!.errorCode, 'commandIdCollision');
    expect(reply.commandResolution!.publicResult, isNull);
  });

  test('planner/request identity disagreement fails closed', () {
    expect(
      () => service.FirstPlayableResponseAdapter.reconnect(
        plan: plan(uncertain: null),
        request: request,
      ),
      throwsA(
        isA<service.AuthorityReconnectViolation>().having(
          (error) => error.code,
          'code',
          'reconnectIdentityMismatch',
        ),
      ),
    );
  });

  test('Roll accepted response carries Engine snapshot and exact versions', () {
    final rollState = syntheticRollState();
    final evaluation = service.AuthorityRollMovementPlanner.evaluate(
      command: syntheticRollCommand(),
      authenticatedActorUid: 'uid-p1',
      memberUidByPlayerId: const <String, String>{'p1': 'uid-p1'},
      state: rollState,
      catalog: syntheticRollCatalog(),
      privateSnapshot: syntheticRollPrivateState(),
      transitionTime: DateTime.parse('2026-08-25T02:00:00.000Z'),
    );

    final reply = service.FirstPlayableResponseAdapter.rollMovement(evaluation);

    expect(reply.status, api.AuthorityCommandStatus.accepted);
    expect(reply.versionBefore, 0);
    expect(reply.versionAfter, 1);
    expect(reply.snapshot!.stateVersion, 1);
    expect(reply.publicResult['events'], isNotEmpty);
  });

  test('Buy rejection stays read-only and exposes only a safe code', () {
    final buyState = syntheticPropertyOfferState();
    final evaluation = service.AuthorityBuyAuctionPlanner.evaluateHuman(
      command: syntheticOfferCommand(
        GameCommandType.buyProperty,
        expectedStateVersion: 99,
      ),
      authenticatedActorUid: 'uid-p1',
      memberUidByPlayerId: const <String, String>{'p1': 'uid-p1'},
      state: buyState,
      catalog: syntheticBuyAuctionCatalog(),
      requestReceivedAt: syntheticBuyAuctionTime,
    );

    final reply = service.FirstPlayableResponseAdapter.buyAuction(evaluation);

    expect(reply.status, api.AuthorityCommandStatus.rejected);
    expect(reply.versionBefore, buyState.header.stateVersion);
    expect(reply.versionAfter, buyState.header.stateVersion);
    expect(reply.errorCode, 'staleVersion');
    expect(reply.snapshot, isNull);
  });

  test('duplicate receipt replays result without a second snapshot', () {
    final receipt = service.DurableCommandReceipt(
      commandId: 'cmd-buy-1',
      inputHashVersion: 1,
      inputHash: identity.inputHash,
      publicResult: const <String, Object?>{
        'commandId': 'cmd-buy-1',
        'status': 'accepted',
        'stateVersionBefore': 1,
        'stateVersionAfter': 2,
        'events': <Object?>[],
      },
    );

    final reply = service.FirstPlayableResponseAdapter.duplicate(receipt);

    expect(reply.status, api.AuthorityCommandStatus.duplicate);
    expect(reply.versionBefore, 1);
    expect(reply.versionAfter, 2);
    expect(reply.snapshot, isNull);
    expect(reply.publicResult, receipt.publicResult);
  });
}

final class _ReconnectTransport implements api.AuthorityWireTransport {
  const _ReconnectTransport(this._response);

  final Map<String, Object?> _response;

  @override
  Future<Map<String, Object?>> reconnect(Map<String, Object?> request) async =>
      _response;

  @override
  Future<Map<String, Object?>> sendCommand(Map<String, Object?> request) =>
      throw UnimplementedError();

  @override
  Stream<Map<String, Object?>> watchPublicGame(String gameId) =>
      const Stream<Map<String, Object?>>.empty();
}
