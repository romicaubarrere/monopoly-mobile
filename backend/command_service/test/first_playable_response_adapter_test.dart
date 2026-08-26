import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart' as service;
import 'package:test/test.dart';

import 'support/synthetic_buy_auction_fixture.dart';

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
