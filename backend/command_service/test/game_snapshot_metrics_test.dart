import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart';
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

// The actual REST store exchanges JSON with a scripted numeric-loopback peer.
// Evaluators supply explicitly synthetic decisions, not Engine gameplay proof.
// This is neither Firestore atomicity evidence nor a measurement of billed I/O.
void main() {
  for (final conflicts in [0, 1, 2]) {
    test(
      'accepted snapshot measures only the final $conflicts-conflict attempt',
      () async {
        final peer = await _Peer.start(conflicts: conflicts);
        addTearDown(peer.close);
        final capture = AuthorityExecutionMetricsCapture();
        final attemptSizes = <int>[];
        late FirstPlayableGameTransactionDecision finalDecision;
        final result = await capture.run(
          () => peer.execute((view) {
            final attempt = attemptSizes.length;
            final state = _state(
              text: List<String>.filled(attempt + 1, 'attempt ñ🎲\\\n"').join(),
            );
            attemptSizes.add(_size(state));
            finalDecision = _accepted(state);
            return finalDecision;
          }),
        );

        expect(result.decision, same(finalDecision));
        expect(attemptSizes, hasLength(conflicts + 1));
        expect(result.metrics.snapshotBytes, attemptSizes.last);
        expect(
          result.metrics.snapshotBytes,
          isNot(_size(syntheticRollState())),
        );
        if (conflicts > 0) {
          expect(result.metrics.snapshotBytes, isNot(attemptSizes.first));
          expect(
            result.metrics.snapshotBytes,
            isNot(attemptSizes.reduce((left, right) => left + right)),
          );
        }
        _expectCounters(result.metrics, peer, conflicts: conflicts, writes: 3);
        _expectCounters(capture.metrics, peer, conflicts: conflicts, writes: 3);
        expect(capture.metrics.snapshotBytes, 0);
        expect(capture.metrics.schemaVersion, isNull);
        expect(capture.metrics.stateVersion, isNull);
        expect(result.metrics.schemaVersion, 1);
        expect(result.metrics.stateVersion, 1);
        expect(peer.commitCalls, conflicts + 1);
        expect(peer.rollbacks, conflicts);
      },
    );
  }

  test('snapshot bytes use canonical UTF-8, including JSON escapes', () async {
    final peer = await _Peer.start();
    addTearDown(peer.close);
    final ascii = CanonicalDomainJson.encode(_state(text: 'a').toJson());
    final state = _state(text: 'ñ🎲\n"\\');
    final expected = ascii.replaceFirst(
      '"measurementFixture":"a"',
      r'"measurementFixture":"ñ🎲\n\"\\"',
    );
    expect(expected, isNot(ascii));
    expect(utf8.encode(expected).length, greaterThan(expected.length));

    final result = await peer.execute((view) => _accepted(state));

    expect(result.metrics.snapshotBytes, utf8.encode(expected).length);
    expect(result.metrics.snapshotBytes, isNot(result.metrics.bytesWritten));
    expect(result.metrics.snapshotBytes, isNot(result.metrics.bytesRead));
    _expectCounters(result.metrics, peer, writes: 3);
  });

  test(
    'receipt and private RNG payload growth do not increase snapshot size',
    () async {
      final small = await _Peer.start();
      final large = await _Peer.start();
      addTearDown(small.close);
      addTearDown(large.close);
      final state = _state(text: 'same public state');
      final first = await small.execute((view) => _accepted(state));
      final second = await large.execute(
        (view) => _accepted(
          state,
          receiptText: List<String>.filled(100, 'receipt-only ñ').join(),
          actorUid: 'uid-${List<String>.filled(30, 'private-owner').join()}',
          rngCounter: 987654321,
        ),
      );

      expect(first.metrics.snapshotBytes, _size(state));
      expect(second.metrics.snapshotBytes, first.metrics.snapshotBytes);
      expect(
        second.metrics.bytesWritten,
        greaterThan(first.metrics.bytesWritten),
      );
      expect(second.metrics.bytesRead, first.metrics.bytesRead);
      _expectCounters(first.metrics, small, writes: 3);
      _expectCounters(second.metrics, large, writes: 3);
    },
  );

  for (final kind in _NoSnapshot.values) {
    test('${kind.name} keeps snapshot size unmeasured', () async {
      final peer = await _Peer.start();
      addTearDown(peer.close);
      final decision = _withoutSnapshot(kind);

      final result = await peer.execute((view) => decision);

      expect(result.decision, same(decision));
      expect(result.metrics.snapshotBytes, 0);
      final writes = kind == _NoSnapshot.rejected ? 1 : 0;
      _expectCounters(result.metrics, peer, writes: writes);
      expect(peer.commitCalls, writes);
      expect(peer.rollbacks, writes == 0 ? 1 : 0);
    });
  }

  test(
    'concurrent game operations retain different final gauges on one store',
    () async {
      final peer = await _Peer.start(interleaveCommits: true);
      addTearDown(peer.close);
      final states = [
        _state(text: 'a'),
        _state(text: 'much longer public ñ🎲'),
      ];
      final captures = [
        AuthorityExecutionMetricsCapture(),
        AuthorityExecutionMetricsCapture(),
      ];
      final results = await Future.wait([
        for (var index = 0; index < states.length; index += 1)
          captures[index].run(
            () => peer.execute(
              (view) => _accepted(states[index], commandId: 'cmd-$index'),
              commandId: 'cmd-$index',
            ),
          ),
      ]);

      expect(results[0].metrics.snapshotBytes, _size(states[0]));
      expect(results[1].metrics.snapshotBytes, _size(states[1]));
      expect(
        results[0].metrics.snapshotBytes,
        isNot(results[1].metrics.snapshotBytes),
      );
      for (var index = 0; index < results.length; index += 1) {
        final metrics = results[index].metrics;
        final transfer = peer.transfers.values.singleWhere(
          (value) => value.commandId == 'cmd-$index',
        );
        expect(metrics.firestoreReadCount, 3);
        expect(metrics.firestoreWriteCount, 3);
        expect(metrics.retryCount, 0);
        expect(metrics.conflictCount, 0);
        expect(metrics.bytesRead, transfer.responseBytes);
        expect(metrics.bytesWritten, transfer.requestBytes);
        expect(_additive(captures[index].metrics), _additive(metrics));
        expect(captures[index].metrics.snapshotBytes, 0);
      }
      expect(peer.commitCalls, 2);
      expect(peer.confirmedWrites, 6);
      expect(peer.rollbacks, 0);
    },
  );

  for (final conflicts in [false, true]) {
    test(
      '${conflicts ? 'exhausted conflicts' : 'failed commit'} exposes no accepted gauge',
      () async {
        final peer = await _Peer.start(
          conflicts: conflicts ? 3 : 0,
          failCommit: !conflicts,
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
                return _accepted(_state(text: 'never confirmed'));
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
            'safe original store classification',
            conflicts ? 'transactionConflict' : 'firestoreUnavailable',
          ),
        );
        expect(identical(propagated, original), isTrue);
        expect(propagatedStack.toString(), originalStack.toString());
        expect(evaluations, conflicts ? 3 : 1);
        expect(capture.metrics.snapshotBytes, 0);
        expect(capture.metrics.schemaVersion, isNull);
        expect(capture.metrics.stateVersion, isNull);
        expect(capture.metrics.retryCount, conflicts ? 2 : 0);
        expect(capture.metrics.conflictCount, conflicts ? 3 : 0);
        expect(capture.metrics.firestoreReadCount, evaluations * 3);
        expect(capture.metrics.firestoreWriteCount, 0);
        expect(capture.metrics.bytesRead, peer.responseBytes);
        expect(capture.metrics.bytesWritten, peer.requestBytes);
        expect(peer.confirmedWrites, 0);
        expect(peer.commitCalls, evaluations);
        expect(peer.rollbacks, evaluations);
      },
    );
  }

  test('diagnostic public validation fails open after one successful commit', () async {
    final peer = await _Peer.start();
    addTearDown(peer.close);
    // Deliberately synthetic adapter input: the existing persistence projection
    // encodes this key, while the stricter public wire wrapper rejects it. This
    // is not a valid Engine/HTTP response or permission to expose private data.
    final state = _state(text: 'a', invalidPublicWrapper: true);
    expect(
      () => api.AuthorityPublicSnapshot(state.toJson()),
      throwsA(
        isA<api.ClientAuthorityContractViolation>().having(
          (error) => error.code,
          'safe validation error',
          'privateMaterialForbidden',
        ),
      ),
    );
    final decision = _accepted(state);
    final capture = AuthorityExecutionMetricsCapture();
    var evaluations = 0;
    final result = await capture.run(
      () => peer.execute((view) {
        evaluations += 1;
        return decision;
      }),
    );

    expect(result.decision, same(decision));
    expect(result.decision.reply.status, api.AuthorityCommandStatus.accepted);
    expect(result.decision.publicStateAfter, same(state));
    expect(result.metrics.snapshotBytes, 0);
    expect(result.metrics.schemaVersion, 1);
    expect(result.metrics.stateVersion, 1);
    expect(evaluations, 1);
    expect(peer.commitCalls, 1);
    expect(peer.rollbacks, 0);
    _expectCounters(result.metrics, peer, writes: 3);
    _expectCounters(capture.metrics, peer, writes: 3);
    expect(capture.metrics.snapshotBytes, 0);
  });

  test(
    'ingress logs the final gauge once with only existing safe fields',
    () async {
      final peer = await _Peer.start(conflicts: 1);
      addTearDown(peer.close);
      final sink = _Sink();
      final ingress = CommandIngress(
        observability: BestEffortAuthorityObservability(sink),
      );
      final state = _state(text: 'public measurement ñ🎲');
      final decision = _accepted(state);
      final reply = await ingress.handle(
        command: const IngressCommandEnvelope(
          kind: IngressCommandKind.game,
          commandId: _commandId,
          inputHashVersion: 1,
          expectedVersion: 0,
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
      expect(event['snapshotBytes'], _size(state));
      expect(event['operation'], 'gameCommand');
      expect(event['outcome'], 'success');
      expect(event['reason'], 'none');
      expect(event['retryCount'], 1);
      expect(event['conflictCount'], 1);
      expect(event['firestoreReadCount'], 6);
      expect(event['firestoreWriteCount'], 3);
      expect(event['bytesRead'], peer.responseBytes);
      expect(event['bytesWritten'], peer.requestBytes);
      expect(event['schemaVersion'], 1);
      expect(event['stateVersion'], 1);
      expect(event['coldStart'], isFalse);
      expect(
        event.keys,
        unorderedEquals([
          'operation',
          'outcome',
          'reason',
          'latencyMs',
          'retryCount',
          'conflictCount',
          'firestoreReadCount',
          'firestoreWriteCount',
          'bytesRead',
          'bytesWritten',
          'snapshotBytes',
          'schemaVersion',
          'stateVersion',
          'coldStart',
        ]),
      );
      final logged = jsonEncode(event);
      for (final privateOrContent in [
        _gameId,
        _commandId,
        _actorUid,
        _inputHash,
        'measurementFixture',
        'public measurement',
        'receipt-only',
        'seedBytes',
        'streamCounters',
        'memberUidByPlayerId',
        'Bearer',
        base64Encode(syntheticRollSeed),
      ]) {
        expect(
          logged.contains(privateOrContent),
          isFalse,
          reason:
              'diagnostics must contain only the safe numeric/enum allowlist',
        );
      }
    },
  );
}

int _size(PublicGameState state) =>
    utf8.encode(CanonicalDomainJson.encode(state.toJson())).length;

PublicGameState _state({
  required String text,
  bool invalidPublicWrapper = false,
}) {
  final base = syntheticRollState(stateVersion: 1);
  return PublicGameState(
    header: base.header,
    presetConfig: base.presetConfig,
    roundState: base.roundState,
    turnState: {
      ...base.turnState,
      'measurementFixture': text,
      if (invalidPublicWrapper) 'token': 'synthetic-diagnostic-only',
    },
    players: base.players,
    seatControllers: base.seatControllers,
    board: base.board,
    ownership: base.ownership,
    bank: base.bank,
    freeParkingPot: base.freeParkingPot,
    deckPublicState: base.deckPublicState,
    lastMutation: base.lastMutation,
  );
}

FirstPlayableGameTransactionDecision _accepted(
  PublicGameState state, {
  String commandId = _commandId,
  String receiptText = 'receipt-only',
  String actorUid = _actorUid,
  int rngCounter = 1,
}) {
  final reply = api.AuthorityCommandReply(
    commandId: commandId,
    status: api.AuthorityCommandStatus.accepted,
    versionBefore: 0,
    versionAfter: state.header.stateVersion,
    // No reply snapshot: this adapter test must measure publicStateAfter.
    publicResult: {
      'commandId': commandId,
      'status': 'accepted',
      'stateVersionBefore': 0,
      'stateVersionAfter': state.header.stateVersion,
      'summary': receiptText,
    },
  );
  return FirstPlayableGameTransactionDecision(
    reply: reply,
    outcome: AuthorityOutcome.success,
    reason: AuthorityReason.none,
    publicStateAfter: state,
    privateRngAfter: AuthorityPrivateRngSnapshot(
      rngVersion: canonicalRngVersion,
      seed: syntheticRollSeed,
      streamCounters: {RngStream.dice: rngCounter},
    ),
    receiptToPersist: StoredAuthorityCommandReceipt(
      actorUid: actorUid,
      receipt: DurableCommandReceipt(
        commandId: commandId,
        inputHashVersion: 1,
        inputHash: _inputHash,
        publicResult: reply.publicResult,
      ),
    ),
  );
}

enum _NoSnapshot { rejected, noOp, duplicate, collision }

FirstPlayableGameTransactionDecision _withoutSnapshot(_NoSnapshot kind) {
  final duplicate = kind == _NoSnapshot.duplicate;
  final reply = api.AuthorityCommandReply(
    commandId: _commandId,
    status: duplicate
        ? api.AuthorityCommandStatus.duplicate
        : api.AuthorityCommandStatus.rejected,
    versionBefore: 0,
    versionAfter: 0,
    errorCode: duplicate ? null : 'staleVersion',
    publicResult: const {'status': 'rejected'},
  );
  return FirstPlayableGameTransactionDecision(
    reply: reply,
    outcome: switch (kind) {
      _NoSnapshot.duplicate => AuthorityOutcome.duplicate,
      _NoSnapshot.collision => AuthorityOutcome.collision,
      _ => AuthorityOutcome.rejected,
    },
    reason: duplicate ? AuthorityReason.duplicateCommand : AuthorityReason.none,
    receiptToPersist: kind != _NoSnapshot.rejected
        ? null
        : StoredAuthorityCommandReceipt(
            actorUid: _actorUid,
            receipt: DurableCommandReceipt(
              commandId: _commandId,
              inputHashVersion: 1,
              inputHash: _inputHash,
              publicResult: reply.publicResult,
            ),
          ),
  );
}

List<int> _additive(AuthorityExecutionMetrics value) => [
  value.retryCount,
  value.conflictCount,
  value.firestoreReadCount,
  value.firestoreWriteCount,
  value.bytesRead,
  value.bytesWritten,
];

void _expectCounters(
  AuthorityExecutionMetrics metrics,
  _Peer peer, {
  int conflicts = 0,
  required int writes,
}) {
  expect(metrics.retryCount, conflicts);
  expect(metrics.conflictCount, conflicts);
  expect(metrics.firestoreReadCount, 3 * (conflicts + 1));
  expect(metrics.firestoreWriteCount, writes);
  expect(metrics.bytesRead, peer.responseBytes);
  expect(metrics.bytesWritten, peer.requestBytes);
  expect(metrics.bytesRead, greaterThan(0));
  expect(metrics.bytesWritten, greaterThan(0));
  expect(metrics.coldStart, isFalse);
  expect(peer.confirmedWrites, writes);
}

final class _Peer {
  _Peer(this.server, this.conflicts, this.failCommit, this.interleaveCommits) {
    store = FirstPlayableFirestoreRestStore(
      config: FirstPlayableFirestoreRestConfig.emulator(
        projectId: 'demo-game-snapshot-size',
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
    bool interleaveCommits = false,
  }) async => _Peer(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    conflicts,
    failCommit,
    interleaveCommits,
  );

  final HttpServer server;
  final HttpClient client = HttpClient();
  late final FirstPlayableFirestoreRestStore store;
  int conflicts;
  final bool failCommit;
  final bool interleaveCommits;
  final transfers = <String, _Transfer>{};
  final _bothCommits = Completer<void>();
  int commitCalls = 0;
  int rollbacks = 0;
  int confirmedWrites = 0;
  int get requestBytes =>
      transfers.values.fold(0, (sum, value) => sum + value.requestBytes);
  int get responseBytes =>
      transfers.values.fold(0, (sum, value) => sum + value.responseBytes);

  Future<FirstPlayableGameTransactionResult> execute(
    FirstPlayableGameTransactionCallback evaluate, {
    String commandId = _commandId,
  }) => store.transactGame(
    gameId: _gameId,
    commandId: commandId,
    evaluate: evaluate,
  );

  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      [],
      (buffer, value) => buffer..addAll(value),
    );
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final method = request.uri.path.split(':').last;
    Object response = <String, Object?>{};
    var status = HttpStatus.ok;
    late _Transfer transfer;
    if (method == 'beginTransaction') {
      final transaction = 'synthetic-transaction-${transfers.length}';
      transfer = _Transfer();
      transfers[transaction] = transfer;
      response = {'transaction': transaction};
    } else {
      transfer = transfers[body['transaction']]!;
      switch (method) {
        case 'batchGet':
          final names = (body['documents']! as List).cast<String>();
          transfer.commandId = names.last.split('/').last;
          response = [
            for (final name in names)
              if (_documents[name.split('/documents/').last] case final fields?)
                {
                  'found': {'name': name, 'fields': _fields(fields)},
                }
              else
                {'missing': name},
          ];
        case 'commit':
          commitCalls += 1;
          if (interleaveCommits) {
            if (commitCalls == 2) _bothCommits.complete();
            await _bothCommits.future.timeout(const Duration(seconds: 5));
          }
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
    }
    final encoded = utf8.encode(jsonEncode(response));
    transfer.requestBytes += bytes.length;
    transfer.responseBytes += encoded.length;
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

final class _Transfer {
  String? commandId;
  int requestBytes = 0;
  int responseBytes = 0;
}

final _documents = <String, Map<String, Object?>>{
  'games/$_gameId': {
    'schemaVersion': 1,
    'stateVersion': 0,
    'memberUids': ['uid-p1', 'uid-p2'],
    'publicState': syntheticRollState().toJson(),
  },
  'gameSecrets/$_gameId': {
    'schemaVersion': 1,
    'rngVersion': canonicalRngVersion,
    'seedBytes': Uint8List.fromList(syntheticRollSeed),
    'streamCounters': {for (final stream in RngStream.values) stream.label: 0},
    'memberUidByPlayerId': {'p1': 'uid-p1', 'p2': 'uid-p2'},
  },
};

Map<String, Object?> _fields(Map<String, Object?> value) => {
  for (final entry in value.entries) entry.key: _value(entry.value),
};

Map<String, Object?> _value(Object? value) => switch (value) {
  null => {'nullValue': null},
  final bool value => {'booleanValue': value},
  final int value => {'integerValue': value.toString()},
  final String value => {'stringValue': value},
  final Uint8List value => {'bytesValue': base64Encode(value)},
  final List<Object?> value => {
    'arrayValue': {'values': value.map(_value).toList()},
  },
  final Map<String, Object?> value => {
    'mapValue': {'fields': _fields(value)},
  },
  _ => throw StateError('unsupportedSyntheticFixtureValue'),
};

final class _Sink implements AuthorityLogSink {
  final events = <Map<String, Object>>[];
  @override
  void write(Map<String, Object> fields) => events.add(fields);
}

const _gameId = 'game-vp0';
const _commandId = 'cmd-snapshot-size';
const _actorUid = 'uid-p1';
final _inputHash = List<String>.filled(64, 'a').join();
