import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart';
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

// Real REST adapter, scripted numeric-loopback peer, synthetic StartGame plans.
// The existing planner supplies the base fixture; modified candidates below
// test accounting, not Engine validity, atomicity or material-factory lifetime.
void main() {
  for (final conflicts in [0, 1, 2]) {
    test(
      'StartGame measures only the final $conflicts-conflict candidate',
      () async {
        final peer = await _Peer.start(conflicts: conflicts);
        addTearDown(peer.close);
        final capture = AuthorityExecutionMetricsCapture();
        final sizes = <int>[];
        late FirstPlayableRoomTransactionDecision decision;
        final result = await capture.run(
          () => peer.execute((view) {
            final plan = _plan(
              List.filled(sizes.length + 1, 'public ñ🎲').join(),
            );
            sizes.add(_size(plan));
            decision = _decision(plan: plan);
            return decision;
          }),
        );

        expect(result.decision, same(decision));
        expect(sizes, hasLength(conflicts + 1));
        expect(result.metrics.snapshotBytes, sizes.last);
        if (conflicts > 0) {
          expect(result.metrics.snapshotBytes, isNot(sizes.first));
          expect(
            result.metrics.snapshotBytes,
            isNot(sizes.reduce((a, b) => a + b)),
          );
        }
        expect(result.metrics.schemaVersion, 1);
        expect(result.metrics.stateVersion, _roomVersion + 1);
        expect(decision.startPlan!.publicState.header.stateVersion, 0);
        _counters(result.metrics, peer, attempts: conflicts + 1, writes: 4);
        _counters(capture.metrics, peer, attempts: conflicts + 1, writes: 4);
        expect(capture.metrics.snapshotBytes, 0);
        expect(capture.metrics.schemaVersion, isNull);
        expect(capture.metrics.stateVersion, isNull);
        expect(peer.commits, conflicts + 1);
        expect(peer.rollbacks, conflicts);
      },
    );
  }

  test(
    'initial game size uses UTF-8 JSON escapes, not room or reply bytes',
    () async {
      final peer = await _Peer.start();
      addTearDown(peer.close);
      final ascii = CanonicalDomainJson.encode(_plan('a').publicState.toJson());
      final plan = _plan('ñ🎲\n"\\');
      final expected = ascii.replaceFirst(
        '"measurementFixture":"a"',
        r'"measurementFixture":"ñ🎲\n\"\\"',
      );
      expect(expected, isNot(ascii));
      expect(utf8.encode(expected).length, greaterThan(expected.length));

      final result = await peer.execute((view) => _decision(plan: plan));

      expect(result.metrics.snapshotBytes, utf8.encode(expected).length);
      expect(
        result.metrics.snapshotBytes,
        isNot(
          utf8.encode(CanonicalDomainJson.encode(plan.roomMutation)).length,
        ),
      );
      expect(
        result.metrics.snapshotBytes,
        isNot(
          utf8.encode(jsonEncode(result.decision.reply.toWireJson())).length,
        ),
      );
      expect(result.metrics.snapshotBytes, isNot(result.metrics.bytesWritten));
      _counters(result.metrics, peer, writes: 4);
    },
  );

  test(
    'private deck, receipt and room-version growth do not change game gauge',
    () async {
      final small = await _Peer.start();
      final large = await _Peer.start();
      addTearDown(small.close);
      addTearDown(large.close);
      final initial = _plan('same public game');
      final larger = _plan(
        'same public game',
        largerPrivateState: true,
        roomVersion: 999999,
      );
      final first = await small.execute((view) => _decision(plan: initial));
      final second = await large.execute(
        (view) => _decision(
          plan: larger,
          receiptText: List.filled(50, 'receipt only ñ').join(),
        ),
      );

      expect(first.metrics.snapshotBytes, _size(initial));
      expect(second.metrics.snapshotBytes, first.metrics.snapshotBytes);
      expect(
        second.metrics.bytesWritten,
        greaterThan(first.metrics.bytesWritten),
      );
      expect(second.metrics.bytesRead, first.metrics.bytesRead);
      expect(first.metrics.stateVersion, _roomVersion + 1);
      expect(second.metrics.stateVersion, 1000000);
      expect(larger.publicState.header.stateVersion, 0);
      _counters(first.metrics, small, writes: 4);
      _counters(second.metrics, large, writes: 4);
    },
  );

  for (final kind in _WithoutGame.values) {
    test('${kind.name} has no initial game gauge', () async {
      final peer = await _Peer.start();
      addTearDown(peer.close);
      final decision = _decision(kind: kind);
      final result = await peer.execute((view) => decision);

      expect(result.decision, same(decision));
      expect(result.metrics.snapshotBytes, 0);
      final writes = switch (kind) {
        _WithoutGame.setReady => 2,
        _WithoutGame.rejected => 1,
        _ => 0,
      };
      _counters(result.metrics, peer, writes: writes);
      expect(peer.commits, writes == 0 ? 0 : 1);
      expect(peer.rollbacks, writes == 0 ? 1 : 0);
    });
  }

  for (final exhausted in [false, true]) {
    test(
      '${exhausted ? 'exhausted retries' : 'commit failure'} preserves error and unmeasured capture',
      () async {
        final peer = await _Peer.start(
          conflicts: exhausted ? 3 : 0,
          failCommit: !exhausted,
        );
        addTearDown(peer.close);
        final capture = AuthorityExecutionMetricsCapture();
        var evaluations = 0;
        Object? original;
        StackTrace? originalStack;
        Object? propagated;
        StackTrace? propagatedStack;
        try {
          await capture.run(() async {
            try {
              return await peer.execute((view) {
                evaluations += 1;
                return _decision(plan: _plan('uncommitted'));
              });
            } on Object catch (error, stack) {
              original = error;
              originalStack = stack;
              rethrow;
            }
          });
        } on Object catch (error, stack) {
          propagated = error;
          propagatedStack = stack;
        }

        expect(
          original,
          isA<FirstPlayableFirestoreStoreViolation>().having(
            (error) => error.code,
            'safe original classification',
            exhausted ? 'transactionConflict' : 'firestoreUnavailable',
          ),
        );
        expect(identical(propagated, original), isTrue);
        expect(propagatedStack.toString(), originalStack.toString());
        final attempts = exhausted ? 3 : 1;
        expect(evaluations, attempts);
        _counters(
          capture.metrics,
          peer,
          attempts: attempts,
          writes: 0,
          conflicts: exhausted ? 3 : 0,
        );
        expect(capture.metrics.snapshotBytes, 0);
        expect(capture.metrics.schemaVersion, isNull);
        expect(capture.metrics.stateVersion, isNull);
        expect(peer.commits, attempts);
        expect(peer.rollbacks, attempts);
      },
    );
  }

  test('post-commit public validation failure leaves accepted StartGame intact', () async {
    final peer = await _Peer.start();
    addTearDown(peer.close);
    // Synthetic direct-adapter input: persistence encodes this fixture's key,
    // but the public wrapper rejects it. This is not valid Engine/HTTP evidence
    // and must never be used as permission to publish private material.
    final plan = _plan('synthetic', invalidPublicWrapper: true);
    expect(
      () => api.AuthorityPublicSnapshot(plan.publicState.toJson()),
      throwsA(
        isA<api.ClientAuthorityContractViolation>().having(
          (error) => error.code,
          'safe validation code',
          'privateMaterialForbidden',
        ),
      ),
    );
    final decision = _decision(plan: plan);
    final capture = AuthorityExecutionMetricsCapture();
    var evaluations = 0;
    final result = await capture.run(
      () => peer.execute((view) {
        evaluations += 1;
        return decision;
      }),
    );

    expect(result.decision, same(decision));
    expect(result.decision.startPlan, same(plan));
    expect(result.decision.reply.status, api.AuthorityCommandStatus.accepted);
    expect(result.metrics.snapshotBytes, 0);
    expect(result.metrics.stateVersion, _roomVersion + 1);
    expect(result.metrics.schemaVersion, 1);
    _counters(result.metrics, peer, writes: 4);
    _counters(capture.metrics, peer, writes: 4);
    expect(capture.metrics.snapshotBytes, 0);
    expect(evaluations, 1);
    expect(peer.commits, 1);
    expect(peer.rollbacks, 0);
  });

  test(
    'roomCommand emits game gauge once while retaining room result version',
    () async {
      final peer = await _Peer.start(conflicts: 1);
      addTearDown(peer.close);
      final sink = _Sink();
      final ingress = CommandIngress(
        observability: BestEffortAuthorityObservability(sink),
      );
      final plan = _plan('public content ñ🎲');
      final decision = _decision(plan: plan);
      final reply = await ingress.handle(
        command: const IngressCommandEnvelope(
          kind: IngressCommandKind.room,
          commandId: _commandId,
          inputHashVersion: 1,
          expectedVersion: _roomVersion,
        ),
        execute: (context, command) async {
          final result = await peer.execute((view) => decision);
          return AuthorityExecutionResult(
            value: result.decision.reply,
            outcome: result.decision.outcome,
            reason: result.decision.reason,
            metrics: result.metrics,
          );
        },
      );

      expect(reply, same(decision.reply));
      expect(sink.events, hasLength(1));
      final event = sink.events.single;
      expect(event, {
        'operation': 'roomCommand',
        'outcome': 'success',
        'reason': 'none',
        'latencyMs': isNonNegative,
        'retryCount': 1,
        'conflictCount': 1,
        'firestoreReadCount': 6,
        'firestoreWriteCount': 4,
        'bytesRead': peer.responseBytes,
        'bytesWritten': peer.requestBytes,
        'snapshotBytes': _size(plan),
        'schemaVersion': 1,
        'stateVersion': _roomVersion + 1,
        'coldStart': false,
      });
      expect(plan.publicState.header.stateVersion, 0);
      final logged = jsonEncode(event);
      for (final privateOrContent in [
        _roomId,
        _commandId,
        'game-vp0',
        'uid-p1',
        'uid-p2',
        _inputHash,
        'measurementFixture',
        'public content',
        'privateDeckState',
        'cardsAOrder',
        'seedBytes',
        'streamCounters',
        'memberUidByPlayerId',
        'Bearer',
        base64Encode(syntheticRollSeed),
      ]) {
        expect(
          logged.contains(privateOrContent),
          isFalse,
          reason: 'only the existing fourteen safe fields may reach the sink',
        );
      }
    },
  );
}

int _size(ReadyStartPlan plan) =>
    utf8.encode(CanonicalDomainJson.encode(plan.publicState.toJson())).length;

final _basePlan = ReadyStartPlanner.plan(
  command: RoomCommand(
    commandId: _commandId,
    schemaVersion: 1,
    expectedRoomVersion: _roomVersion,
    clientInstanceId: 'synthetic-client',
    type: RoomCommandType.startGame,
    payload: const {'roomId': _roomId},
  ),
  authenticatedActorUid: 'uid-p1',
  hostUid: 'uid-p1',
  gameId: 'game-vp0',
  presetId: 'express',
  members: _members,
  catalog: syntheticRollCatalog(),
  secureSeed: syntheticRollSeed,
);

ReadyStartPlan _plan(
  String text, {
  bool invalidPublicWrapper = false,
  bool largerPrivateState = false,
  int roomVersion = _roomVersion,
}) {
  final state = _basePlan.publicState;
  return ReadyStartPlan(
    commandId: _commandId,
    roomId: _roomId,
    roomVersionBefore: roomVersion,
    gameId: state.header.gameId,
    starterAllocation: _basePlan.starterAllocation,
    publicState: PublicGameState(
      header: state.header,
      presetConfig: state.presetConfig,
      roundState: state.roundState,
      turnState: {
        ...state.turnState,
        'measurementFixture': text,
        if (invalidPublicWrapper) 'token': 'synthetic-diagnostic-only',
      },
      players: state.players,
      seatControllers: state.seatControllers,
      board: state.board,
      ownership: state.ownership,
      bank: state.bank,
      freeParkingPot: state.freeParkingPot,
      deckPublicState: state.deckPublicState,
      lastMutation: state.lastMutation,
    ),
    privateState: !largerPrivateState
        ? _basePlan.privateState
        : ReadyStartPrivateState(
            seed: syntheticRollSeed,
            streamCounters: {
              for (final stream in RngStream.values) stream: 987654321,
            },
            cardsAOrder: List.filled(50, 'synthetic-private-card-a'),
            cardsBOrder: List.filled(50, 'synthetic-private-card-b'),
          ),
  );
}

enum _WithoutGame { rejected, setReady, duplicate, collision, noWrite }

FirstPlayableRoomTransactionDecision _decision({
  ReadyStartPlan? plan,
  _WithoutGame kind = _WithoutGame.rejected,
  String receiptText = 'safe summary',
}) {
  final accepted = plan != null || kind == _WithoutGame.setReady;
  final duplicate = !accepted && kind == _WithoutGame.duplicate;
  final persistReceipt = accepted || kind == _WithoutGame.rejected;
  final before = plan?.roomVersionBefore ?? _roomVersion;
  final after = accepted ? before + 1 : before;
  final reply = api.AuthorityCommandReply(
    commandId: _commandId,
    status: accepted
        ? api.AuthorityCommandStatus.accepted
        : duplicate
        ? api.AuthorityCommandStatus.duplicate
        : api.AuthorityCommandStatus.rejected,
    versionBefore: before,
    versionAfter: after,
    errorCode: accepted || duplicate
        ? null
        : kind == _WithoutGame.collision
        ? 'commandIdCollision'
        : 'staleRoomVersion',
    publicResult: {
      'status': accepted ? 'accepted' : 'rejected',
      'summary': receiptText,
    },
  );
  return FirstPlayableRoomTransactionDecision(
    reply: reply,
    outcome: accepted
        ? AuthorityOutcome.success
        : duplicate
        ? AuthorityOutcome.duplicate
        : kind == _WithoutGame.collision
        ? AuthorityOutcome.collision
        : AuthorityOutcome.rejected,
    reason: AuthorityReason.none,
    startPlan: plan,
    startMemberUidByPlayerId: plan == null
        ? null
        : const {'p1': 'uid-p1', 'p2': 'uid-p2'},
    membersAfter: plan == null && kind == _WithoutGame.setReady
        ? _members
        : null,
    receiptToPersist: !persistReceipt
        ? null
        : StoredAuthorityCommandReceipt(
            actorUid: 'uid-p1',
            receipt: DurableCommandReceipt(
              commandId: _commandId,
              inputHashVersion: 1,
              inputHash: _inputHash,
              publicResult: reply.publicResult,
            ),
          ),
  );
}

void _counters(
  AuthorityExecutionMetrics metrics,
  _Peer peer, {
  int attempts = 1,
  required int writes,
  int? conflicts,
}) {
  expect(metrics.retryCount, attempts - 1);
  expect(metrics.conflictCount, conflicts ?? attempts - 1);
  expect(metrics.firestoreReadCount, 3 * attempts);
  expect(metrics.firestoreWriteCount, writes);
  expect(metrics.bytesRead, peer.responseBytes);
  expect(metrics.bytesWritten, peer.requestBytes);
  expect(metrics.bytesRead, greaterThan(0));
  expect(metrics.bytesWritten, greaterThan(0));
  expect(metrics.coldStart, isFalse);
  expect(peer.confirmedWrites, writes);
}

final class _Peer {
  _Peer(this.server, this.conflicts, this.failCommit) {
    store = FirstPlayableFirestoreRestStore(
      config: FirstPlayableFirestoreRestConfig.emulator(
        projectId: 'demo-start-game-size',
        host: '127.0.0.1:${server.port}',
        maxAttempts: 3,
      ),
      httpClient: client,
    );
    server.listen(_handle);
  }

  static Future<_Peer> start({
    int conflicts = 0,
    bool failCommit = false,
  }) async => _Peer(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    conflicts,
    failCommit,
  );

  final HttpServer server;
  final HttpClient client = HttpClient();
  late final FirstPlayableFirestoreRestStore store;
  int conflicts;
  final bool failCommit;
  int begins = 0;
  int commits = 0;
  int rollbacks = 0;
  int confirmedWrites = 0;
  int requestBytes = 0;
  int responseBytes = 0;

  Future<FirstPlayableRoomTransactionResult> execute(
    FirstPlayableRoomTransactionCallback evaluate,
  ) => store.transactRoom(
    roomId: _roomId,
    commandId: _commandId,
    evaluate: evaluate,
  );

  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    requestBytes += bytes.length;
    Object response = <String, Object?>{};
    var status = HttpStatus.ok;
    switch (request.uri.path.split(':').last) {
      case 'beginTransaction':
        response = {'transaction': 'synthetic-start-${++begins}'};
      case 'batchGet':
        response = [
          for (final name in (body['documents']! as List).cast<String>())
            if (_documents[name.split('/documents/').last] case final fields?)
              {
                'found': {'name': name, 'fields': _fields(fields)},
              }
            else
              {'missing': name},
        ];
      case 'commit':
        commits += 1;
        if (failCommit || conflicts > 0) {
          if (!failCommit) conflicts -= 1;
          status = failCommit
              ? HttpStatus.serviceUnavailable
              : HttpStatus.conflict;
          response = {
            'error': {'status': failCommit ? 'UNAVAILABLE' : 'ABORTED'},
          };
        } else {
          confirmedWrites += (body['writes']! as List).length;
        }
      case 'rollback':
        rollbacks += 1;
      default:
        status = HttpStatus.notFound;
    }
    final encoded = utf8.encode(jsonEncode(response));
    responseBytes += encoded.length;
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.add(encoded);
    await request.response.close();
  }

  Future<void> close() async {
    client.close(force: true);
    await server.close(force: true);
  }
}

Map<String, Object?> _fields(Map<String, Object?> value) => {
  for (final entry in value.entries) entry.key: _value(entry.value),
};
Map<String, Object?> _value(Object? value) => switch (value) {
  final String value => {'stringValue': value},
  final int value => {'integerValue': value.toString()},
  final bool value => {'booleanValue': value},
  final List<Object?> value => {
    'arrayValue': {'values': value.map(_value).toList()},
  },
  final Map<String, Object?> value => {
    'mapValue': {'fields': _fields(value)},
  },
  _ => throw StateError('unsupportedSyntheticRoomFixture'),
};

const _documents = <String, Map<String, Object?>>{
  'rooms/$_roomId': {
    'schemaVersion': 1,
    'roomId': _roomId,
    'roomVersion': _roomVersion,
    'status': 'open',
    'hostUid': 'uid-p1',
    'presetId': 'express',
    'frozenRulesVersion': 'synthetic-rules-vp0',
    'memberUids': ['uid-p1', 'uid-p2'],
    'readyByUid': {'uid-p1': true, 'uid-p2': true},
  },
  'roomSecrets/$_roomId': {
    'schemaVersion': 1,
    'memberUidByPlayerId': {'p1': 'uid-p1', 'p2': 'uid-p2'},
  },
};
const _members = [
  ReadyRoomMember(
    uid: 'uid-p1',
    playerId: 'p1',
    kind: PlayerKind.human,
    ready: true,
  ),
  ReadyRoomMember(
    uid: 'uid-p2',
    playerId: 'p2',
    kind: PlayerKind.human,
    ready: true,
  ),
];
const _roomId = 'room-vp0';
const _roomVersion = 7;
const _commandId = 'cmd-start-size';
final _inputHash = List.filled(64, 'a').join();

final class _Sink implements AuthorityLogSink {
  final events = <Map<String, Object>>[];
  @override
  void write(Map<String, Object> fields) => events.add(fields);
}
