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

// This scripted numeric-loopback REST peer measures actual JSON exchanges. It
// is not a Firestore concurrency/atomicity emulator or production billing proof.
void main() {
  for (final family in _Family.values) {
    for (final conflicts in <int>[0, 1, 2]) {
      test('${family.name} accumulates $conflicts commit conflicts', () async {
        final peer = await _RestPeer.start(commitConflicts: conflicts);
        addTearDown(peer.close);
        var evaluations = 0;
        final metrics = await peer.execute(
          family,
          onEvaluate: () => evaluations += 1,
        );

        expect(evaluations, conflicts + 1);
        expect(metrics.retryCount, conflicts);
        expect(metrics.conflictCount, conflicts);
        expect(metrics.firestoreReadCount, family.reads * (conflicts + 1));
        expect(metrics.firestoreWriteCount, 1);
        expect(peer.confirmedWrites, 1);
        expect(peer.rollbacks, conflicts);
        peer.expectTransferTotals(metrics);
        expect(metrics.schemaVersion, 1);
        expect(metrics.stateVersion, 0);
      });
    }

    test('${family.name} no-write result measures rollback only', () async {
      final peer = await _RestPeer.start();
      addTearDown(peer.close);
      final metrics = await peer.execute(family, noWrite: true);

      expect(metrics.firestoreReadCount, family.reads);
      expect(metrics.firestoreWriteCount, 0);
      expect(peer.commitCalls, 0);
      expect(peer.rollbacks, 1);
      peer.expectTransferTotals(metrics);
    });

    test(
      '${family.name} batch conflict includes error exchange bytes',
      () async {
        final peer = await _RestPeer.start(batchConflicts: 1);
        addTearDown(peer.close);
        var evaluations = 0;
        final metrics = await peer.execute(
          family,
          onEvaluate: () => evaluations += 1,
        );

        expect(evaluations, 1);
        expect(metrics.retryCount, 1);
        // A failed batch has no confirmed document reads, but its payload bytes
        // and rollback exchange must not disappear from the operation totals.
        expect(metrics.firestoreReadCount, family.reads);
        expect(metrics.firestoreWriteCount, 1);
        peer.expectTransferTotals(metrics);
      },
    );
  }

  for (final game in <bool>[false, true]) {
    test(
      '${game ? 'game' : 'room'} read retains complete request metrics',
      () async {
        final peer = await _RestPeer.start();
        addTearDown(peer.close);
        final metrics = game
            ? (await peer.store.readGame(gameId: 'game-vp0')).metrics
            : (await peer.store.readRoom(roomId: 'room-vp0')).metrics;

        expect(metrics.firestoreReadCount, 2);
        expect(metrics.firestoreWriteCount, 0);
        expect(metrics.retryCount, 0);
        expect(peer.rollbacks, 1);
        peer.expectTransferTotals(metrics);
      },
    );
  }

  test('failed cleanup bytes survive a later successful retry', () async {
    final peer = await _RestPeer.start(commitConflicts: 1, rollbackFailures: 1);
    addTearDown(peer.close);
    final metrics = await peer.execute(_Family.game);

    expect(metrics.retryCount, 1);
    expect(metrics.firestoreReadCount, 6);
    expect(metrics.firestoreWriteCount, 1);
    peer.expectTransferTotals(metrics);
  });

  test('interleaved operations on one store never share counters', () async {
    final peer = await _RestPeer.start(interleaveCommits: true);
    addTearDown(peer.close);
    final results = await Future.wait(<Future<AuthorityExecutionMetrics>>[
      peer.execute(_Family.room),
      peer.execute(_Family.game),
    ]);

    for (final metrics in results) {
      expect(metrics.firestoreReadCount, 3);
      expect(metrics.firestoreWriteCount, 1);
      expect(metrics.retryCount, 0);
    }
    expect(results[0].bytesRead + results[1].bytesRead, peer.responseBytes);
    expect(
      results[0].bytesWritten + results[1].bytesWritten,
      peer.requestBytes,
    );
  });

  test('retry metrics reach ingress without private payload fields', () async {
    final peer = await _RestPeer.start(commitConflicts: 1);
    addTearDown(peer.close);
    final sink = _Sink();
    final ingress = CommandIngress(
      observability: BestEffortAuthorityObservability(sink),
    );
    final reply = await ingress.handle(
      command: const IngressCommandEnvelope(
        kind: IngressCommandKind.game,
        commandId: 'cmd-metrics',
        inputHashVersion: 1,
        expectedVersion: 0,
      ),
      execute: (context, command) async => AuthorityExecutionResult(
        value: 'safe-result',
        outcome: AuthorityOutcome.rejected,
        reason: AuthorityReason.staleVersion,
        metrics: await peer.execute(_Family.game),
      ),
    );

    expect(reply, 'safe-result');
    expect(sink.events, hasLength(1));
    final event = sink.events.single;
    expect(event['firestoreReadCount'], 6);
    expect(event['firestoreWriteCount'], 1);
    expect(event['bytesRead'], peer.responseBytes);
    expect(event['bytesWritten'], peer.requestBytes);
    expect(
      event.keys,
      unorderedEquals(<String>[
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
        'coldStart',
        'schemaVersion',
        'stateVersion',
      ]),
    );
    final logged = jsonEncode(event);
    for (final secret in <String>[
      'uid-p1',
      'cmd-metrics',
      'seedBytes',
      'streamCounters',
      'Bearer',
      'private-error',
    ]) {
      expect(logged, isNot(contains(secret)));
    }
  });

  test('exhausted conflicts preserve bounded retry and safe failure', () async {
    final peer = await _RestPeer.start(commitConflicts: 5);
    addTearDown(peer.close);
    await expectLater(
      peer.execute(_Family.game),
      throwsA(
        isA<FirstPlayableFirestoreStoreViolation>().having(
          (error) => error.code,
          'safe code',
          'transactionConflict',
        ),
      ),
    );
    expect(peer.commitCalls, 3);
    expect(peer.rollbacks, 3);
    expect(peer.confirmedWrites, 0);
  });
}

enum _Family {
  entry(4),
  room(3),
  game(3);

  const _Family(this.reads);
  final int reads;
}

final class _RestPeer {
  _RestPeer(
    this.server, {
    required this.commitConflicts,
    required this.batchConflicts,
    required this.rollbackFailures,
    required this.interleaveCommits,
  }) {
    store = FirstPlayableFirestoreRestStore(
      config: FirstPlayableFirestoreRestConfig.emulator(
        projectId: 'demo-retry-metrics',
        host: '127.0.0.1:${server.port}',
        maxAttempts: 3,
      ),
      httpClient: client,
    );
    server.listen(_handle);
  }

  static Future<_RestPeer> start({
    int commitConflicts = 0,
    int batchConflicts = 0,
    int rollbackFailures = 0,
    bool interleaveCommits = false,
  }) async => _RestPeer(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    commitConflicts: commitConflicts,
    batchConflicts: batchConflicts,
    rollbackFailures: rollbackFailures,
    interleaveCommits: interleaveCommits,
  );

  final HttpServer server;
  final HttpClient client = HttpClient();
  late final FirstPlayableFirestoreRestStore store;
  int commitConflicts;
  int batchConflicts;
  int rollbackFailures;
  final bool interleaveCommits;
  final Completer<void> _commitsArrived = Completer<void>();
  int _begins = 0;
  int commitCalls = 0;
  int rollbacks = 0;
  int confirmedWrites = 0;
  int requestBytes = 0;
  int responseBytes = 0;

  Future<AuthorityExecutionMetrics> execute(
    _Family family, {
    bool noWrite = false,
    void Function()? onEvaluate,
  }) async {
    final reply = api.AuthorityCommandReply(
      commandId: 'cmd-metrics',
      status: noWrite
          ? api.AuthorityCommandStatus.duplicate
          : api.AuthorityCommandStatus.rejected,
      versionBefore: 0,
      versionAfter: 0,
      errorCode: noWrite ? null : 'staleVersion',
      publicResult: const <String, Object?>{'status': 'rejected'},
    );
    final receipt = noWrite
        ? null
        : StoredAuthorityCommandReceipt(
            actorUid: 'uid-p1',
            receipt: DurableCommandReceipt(
              commandId: 'cmd-metrics',
              inputHashVersion: 1,
              inputHash: List<String>.filled(64, 'a').join(),
              publicResult: reply.publicResult,
            ),
          );
    final outcome = noWrite
        ? AuthorityOutcome.duplicate
        : AuthorityOutcome.rejected;
    final reason = noWrite
        ? AuthorityReason.duplicateCommand
        : AuthorityReason.staleVersion;
    switch (family) {
      case _Family.entry:
        return (await store.transactRoomEntry(
          kind: FirstPlayableRoomEntryKind.create,
          codeHash: List<String>.filled(64, 'b').join(),
          roomId: 'new-room',
          commandId: reply.commandId,
          evaluate: (view) {
            onEvaluate?.call();
            return FirstPlayableRoomEntryTransactionDecision(
              reply: reply,
              outcome: outcome,
              reason: reason,
              receiptToPersist: receipt,
            );
          },
        )).metrics;
      case _Family.room:
        return (await store.transactRoom(
          roomId: 'room-vp0',
          commandId: reply.commandId,
          evaluate: (view) {
            onEvaluate?.call();
            return FirstPlayableRoomTransactionDecision(
              reply: reply,
              outcome: outcome,
              reason: reason,
              receiptToPersist: receipt,
            );
          },
        )).metrics;
      case _Family.game:
        return (await store.transactGame(
          gameId: 'game-vp0',
          commandId: reply.commandId,
          evaluate: (view) {
            onEvaluate?.call();
            return FirstPlayableGameTransactionDecision(
              reply: reply,
              outcome: outcome,
              reason: reason,
              receiptToPersist: receipt,
            );
          },
        )).metrics;
    }
  }

  void expectTransferTotals(AuthorityExecutionMetrics metrics) {
    expect(
      metrics.bytesRead,
      responseBytes,
      reason: 'all response UTF-8 payloads',
    );
    expect(
      metrics.bytesWritten,
      requestBytes,
      reason: 'all request UTF-8 payloads',
    );
  }

  Future<void> close() async {
    client.close(force: true);
    await server.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    requestBytes += bytes.length;
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final method = request.uri.path.split(':').last;
    Object response = <String, Object?>{};
    var status = HttpStatus.ok;
    switch (method) {
      case 'beginTransaction':
        response = <String, Object?>{'transaction': 'transaction-${++_begins}'};
      case 'batchGet':
        if (batchConflicts > 0) {
          batchConflicts -= 1;
          status = HttpStatus.conflict;
          response = _error('ABORTED');
        } else {
          response = <Object?>[
            for (final name in (body['documents']! as List).cast<String>())
              if (_documents[name.split('/documents/').last] case final fields?)
                <String, Object?>{
                  'found': <String, Object?>{
                    'name': name,
                    'fields': _fields(fields),
                  },
                }
              else
                <String, Object?>{'missing': name},
          ];
        }
      case 'commit':
        commitCalls += 1;
        if (interleaveCommits) {
          if (commitCalls == 2) _commitsArrived.complete();
          await _commitsArrived.future;
        }
        if (commitConflicts > 0) {
          commitConflicts -= 1;
          status = HttpStatus.conflict;
          response = _error('ABORTED');
        } else {
          confirmedWrites += (body['writes']! as List).length;
        }
      case 'rollback':
        rollbacks += 1;
        if (rollbackFailures > 0) {
          rollbackFailures -= 1;
          status = HttpStatus.serviceUnavailable;
          response = _error('UNAVAILABLE');
        }
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
}

Map<String, Object?> _error(String status) => <String, Object?>{
  'error': <String, Object?>{'status': status, 'message': 'private-error ñ 🧪'},
};

final Map<String, Map<String, Object?>> _documents =
    <String, Map<String, Object?>>{
      'rooms/room-vp0': <String, Object?>{
        'schemaVersion': 1,
        'roomId': 'room-vp0',
        'roomVersion': 0,
        'status': 'open',
        'hostUid': 'uid-p1',
        'presetId': 'express',
        'frozenRulesVersion': 'synthetic-rules-vp0',
        'memberUids': <String>['uid-p1', 'uid-p2'],
        'readyByUid': <String, bool>{'uid-p1': true, 'uid-p2': true},
      },
      'roomSecrets/room-vp0': <String, Object?>{
        'schemaVersion': 1,
        'memberUidByPlayerId': <String, String>{'p1': 'uid-p1', 'p2': 'uid-p2'},
      },
      'games/game-vp0': <String, Object?>{
        'schemaVersion': 1,
        'stateVersion': 0,
        'memberUids': <String>['uid-p1', 'uid-p2'],
        'publicState': syntheticRollState().toJson(),
      },
      'gameSecrets/game-vp0': <String, Object?>{
        'schemaVersion': 1,
        'rngVersion': canonicalRngVersion,
        'seedBytes': Uint8List.fromList(syntheticRollSeed),
        'streamCounters': <String, int>{
          for (final stream in RngStream.values) stream.label: 0,
        },
        'memberUidByPlayerId': <String, String>{'p1': 'uid-p1', 'p2': 'uid-p2'},
      },
    };

Map<String, Object?> _fields(Map<String, Object?> value) => <String, Object?>{
  for (final entry in value.entries) entry.key: _value(entry.value),
};

Map<String, Object?> _value(Object? value) => switch (value) {
  null => <String, Object?>{'nullValue': null},
  final bool value => <String, Object?>{'booleanValue': value},
  final int value => <String, Object?>{'integerValue': value.toString()},
  final String value => <String, Object?>{'stringValue': value},
  final Uint8List value => <String, Object?>{'bytesValue': base64Encode(value)},
  final List<Object?> value => <String, Object?>{
    'arrayValue': <String, Object?>{'values': value.map(_value).toList()},
  },
  final Map<String, Object?> value => <String, Object?>{
    'mapValue': <String, Object?>{'fields': _fields(value)},
  },
  _ => throw StateError('Unsupported synthetic fixture value'),
};

final class _Sink implements AuthorityLogSink {
  final List<Map<String, Object>> events = <Map<String, Object>>[];

  @override
  void write(Map<String, Object> fields) => events.add(fields);
}
