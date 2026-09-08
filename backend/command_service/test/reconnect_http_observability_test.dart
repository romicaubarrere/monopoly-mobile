import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart' as service;
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

// Real HTTP ingress, executor, reconnect planner and Firestore REST adapter.
// Identity and the REST peer are synthetic numeric-loopback fixtures. These
// tests do not prove Firebase Emulator atomicity, production cost or ACK receipt.
void main() {
  for (final disposition in api.ReconnectDisposition.values) {
    test(
      '${disposition.name} emits technical recovery success without changing its disposition',
      () async {
        final harness = await _Harness.start(disposition: disposition);
        addTearDown(harness.close);
        final response = await harness.reconnect();

        expect(response.status, HttpStatus.ok);
        expect(response.body['disposition'], disposition.wireValue);
        expect(response.body['snapshot'], harness.peer.publicState);
        final resolution = response.body['commandResolution'];
        final expectedAction = switch (disposition) {
          api.ReconnectDisposition.upToDate ||
          api.ReconnectDisposition.snapshotAdvanced => null,
          api.ReconnectDisposition.uncertainConfirmed ||
          api.ReconnectDisposition.uncertainRejected => 'useDurableResult',
          api.ReconnectDisposition.retrySameCommand => 'retrySameCommand',
          api.ReconnectDisposition.semanticCollision => 'failClosed',
        };
        if (expectedAction == null) {
          expect(resolution, isNull);
        } else {
          final fields = resolution! as Map<String, Object?>;
          expect(fields['action'], expectedAction);
          expect(
            fields['identity'],
            harness.reconnectRequest.uncertainCommand!.toWireJson(),
          );
          if (disposition == api.ReconnectDisposition.uncertainRejected) {
            expect((fields['publicResult']! as Map)['status'], 'rejected');
          }
          if (disposition == api.ReconnectDisposition.semanticCollision) {
            expect(fields['errorCode'], 'commandIdCollision');
          }
        }
        final event = harness.onlyEvent;
        _expectSuccess(event, harness.peer.publicState);
        _expectTransfers(event, harness.peer.onlyTransfer);
        expect(event['firestoreReadCount'], expectedAction == null ? 2 : 3);
        expect(harness.peer.methods, <String>[
          'beginTransaction',
          'batchGet',
          'rollback',
        ]);
        _expectSafe(response, event);
      },
    );
  }

  test(
    'another actor receipt remains a fail-closed semantic collision',
    () async {
      final harness = await _Harness.start(
        disposition: api.ReconnectDisposition.uncertainConfirmed,
        receiptActor: 'uid-p2',
      );
      addTearDown(harness.close);
      final response = await harness.reconnect();

      expect(response.status, HttpStatus.ok);
      expect(response.body['disposition'], 'semanticCollision');
      final resolution =
          response.body['commandResolution']! as Map<String, Object?>;
      expect(resolution['action'], 'failClosed');
      expect(resolution, isNot(contains('publicResult')));
      _expectSuccess(harness.onlyEvent, harness.peer.publicState);
      _expectTransfers(harness.onlyEvent, harness.peer.onlyTransfer);
      expect(harness.onlyEvent['firestoreReadCount'], 3);
      _expectSafe(response, harness.onlyEvent);
    },
  );

  for (final failure in <({String name, int status, String code})>[
    (name: 'membership', status: HttpStatus.forbidden, code: 'actorForbidden'),
    (
      name: 'catalog',
      status: HttpStatus.internalServerError,
      code: 'authorityUnavailable',
    ),
    (
      name: 'private snapshot',
      status: HttpStatus.badRequest,
      code: 'privateMaterialForbidden',
    ),
  ]) {
    test(
      '${failure.name} failure retains a completed read and safe HTTP mapping',
      () async {
        final harness = await _Harness.start(
          uid: failure.name == 'membership' ? 'uid-outsider' : _uid,
          invalidCatalog: failure.name == 'catalog',
          privateSnapshot: failure.name == 'private snapshot',
        );
        addTearDown(harness.close);
        final response = await harness.reconnect();

        _expectHttpError(response, failure.status, failure.code);
        final event = harness.onlyEvent;
        _expectFailure(event);
        _expectTransfers(event, harness.peer.onlyTransfer);
        expect(event['firestoreReadCount'], 2);
        expect(harness.peer.methods, <String>[
          'beginTransaction',
          'batchGet',
          'rollback',
        ]);
        _expectSafe(response, event);
      },
    );
  }

  test('a public snapshot with a private receipt still fails before size extraction', () async {
    final harness = await _Harness.start(
      disposition: api.ReconnectDisposition.uncertainConfirmed,
    );
    addTearDown(harness.close);
    final receipt =
        harness.peer.documents['games/$_gameId/commands/$_commandId']!;
    (receipt['resultSummary']! as Map<String, Object?>)['token'] =
        'private-fixture-value';

    final response = await harness.reconnect();

    _expectHttpError(
      response,
      HttpStatus.badRequest,
      'privateMaterialForbidden',
    );
    _expectFailure(harness.onlyEvent);
    _expectTransfers(harness.onlyEvent, harness.peer.onlyTransfer);
    expect(harness.onlyEvent['firestoreReadCount'], 3);
    _expectSafe(response, harness.onlyEvent);
  });

  for (final method in <String>['batchGet', 'rollback']) {
    test(
      '$method error retains completed exchanges without adding retries',
      () async {
        final harness = await _Harness.start(failMethod: method);
        addTearDown(harness.close);
        final response = await harness.reconnect();

        _expectHttpError(
          response,
          HttpStatus.internalServerError,
          'authorityUnavailable',
        );
        final event = harness.onlyEvent;
        _expectFailure(event);
        _expectTransfers(event, harness.peer.onlyTransfer);
        expect(event['firestoreReadCount'], method == 'batchGet' ? 0 : 2);
        expect(harness.peer.methods, <String>[
          'beginTransaction',
          'batchGet',
          'rollback',
          if (method == 'rollback') 'rollback',
        ]);
        _expectSafe(response, event);
      },
    );
  }

  for (final failure in <bool>[false, true]) {
    test(
      'throwing sink preserves ${failure ? 'forbidden response' : 'technical success'}',
      () async {
        final harness = await _Harness.start(
          throwingSink: true,
          uid: failure ? 'uid-outsider' : _uid,
        );
        addTearDown(harness.close);
        final response = await harness.reconnect();

        if (failure) {
          _expectHttpError(response, HttpStatus.forbidden, 'actorForbidden');
          _expectFailure(harness.onlyEvent);
        } else {
          expect(response.status, HttpStatus.ok);
          expect(response.body['disposition'], 'upToDate');
          _expectSuccess(harness.onlyEvent, harness.peer.publicState);
        }
        _expectTransfers(harness.onlyEvent, harness.peer.onlyTransfer);
        _expectSafe(response, harness.onlyEvent);
      },
    );
  }

  test(
    'concurrent duplicate command and recovery isolate actual REST transfers',
    () async {
      final command = api.AuthorityCommandRequest.game(
        syntheticRollCommand(commandId: _commandId),
      );
      final harness = await _Harness.start(
        disposition: api.ReconnectDisposition.uncertainConfirmed,
        receiptHash: command.inputHash,
        interleaveBatches: true,
      );
      addTearDown(harness.close);
      final replies = await Future.wait(<Future<_Response>>[
        harness.request('POST', '/v1/authority/commands', command.toWireJson()),
        harness.request(
          'POST',
          '/v1/authority/reconnect',
          api.AuthorityReconnectRequest(
            gameId: _gameId,
            observedStateVersion: 1,
          ).toWireJson(),
        ),
      ]);

      expect(replies.map((reply) => reply.status), everyElement(HttpStatus.ok));
      expect(replies[0].body['status'], 'duplicate');
      expect(replies[1].body['disposition'], 'upToDate');
      expect(harness.sink.events, hasLength(2));
      final commandEvent = harness.sink.events.singleWhere(
        (event) => event['operation'] == 'gameCommand',
      );
      final recoveryEvent = harness.sink.events.singleWhere(
        (event) => event['operation'] == 'recovery',
      );
      expect(commandEvent['outcome'], 'duplicate');
      expect(commandEvent['firestoreReadCount'], 3);
      expect(commandEvent['firestoreWriteCount'], 0);
      expect(commandEvent['snapshotBytes'], 0);
      _expectSuccess(recoveryEvent, harness.peer.publicState);
      expect(recoveryEvent['firestoreReadCount'], 2);
      _expectTransfers(
        commandEvent,
        harness.peer.transfers.values.singleWhere((value) => !value.readOnly),
      );
      _expectTransfers(
        recoveryEvent,
        harness.peer.transfers.values.singleWhere((value) => value.readOnly),
      );
      expect(
        harness.peer.methods.where((method) => method == 'commit'),
        isEmpty,
      );
      _expectSafe(replies[0], commandEvent);
      _expectSafe(replies[1], recoveryEvent);
    },
  );

  test(
    'snapshot size counts UTF-8 and JSON escaping without logging content',
    () async {
      final harness = await _Harness.start();
      addTearDown(harness.close);
      final turn =
          harness.peer.publicState['turnState']! as Map<String, Object?>;
      turn['measurementFixture'] = 'a';
      final ascii = CanonicalDomainJson.encode(harness.peer.publicState);
      turn['measurementFixture'] = 'ñ🎲\n"\\';
      final expectedJson = ascii.replaceFirst(
        '"measurementFixture":"a"',
        r'"measurementFixture":"ñ🎲\n\"\\"',
      );
      expect(expectedJson, isNot(ascii));

      final response = await harness.reconnect();

      expect(response.status, HttpStatus.ok);
      expect(response.body['snapshot'], harness.peer.publicState);
      expect(
        harness.onlyEvent['snapshotBytes'],
        utf8.encode(expectedJson).length,
      );
      expect(
        utf8.encode(expectedJson).length,
        greaterThan(expectedJson.length),
      );
      _expectSuccess(harness.onlyEvent, harness.peer.publicState);
      _expectTransfers(harness.onlyEvent, harness.peer.onlyTransfer);
      _expectSafe(response, harness.onlyEvent);
      expect(
        jsonEncode(harness.onlyEvent),
        isNot(contains('measurementFixture')),
      );
    },
  );

  test('changing only a durable receipt changes payload bytes but not snapshot size', () async {
    final harness = await _Harness.start(
      disposition: api.ReconnectDisposition.uncertainConfirmed,
    );
    addTearDown(harness.close);
    final before = await harness.reconnect();
    final receipt =
        harness.peer.documents['games/$_gameId/commands/$_commandId']!;
    final result = receipt['resultSummary']! as Map<String, Object?>;
    final publicText = List<String>.filled(20, 'public ñ🎲\n"').join();
    result['measurementFixture'] = publicText;

    final after = await harness.reconnect();

    expect(before.status, HttpStatus.ok);
    expect(after.status, HttpStatus.ok);
    expect(after.body['snapshot'], before.body['snapshot']);
    final resolution = after.body['commandResolution']! as Map<String, Object?>;
    expect(
      (resolution['publicResult']! as Map)['measurementFixture'],
      publicText,
    );
    expect(
      utf8.encode(jsonEncode(after.body)).length,
      greaterThan(utf8.encode(jsonEncode(before.body)).length),
    );
    expect(harness.sink.events, hasLength(2));
    expect(
      harness.sink.events.last['snapshotBytes'],
      harness.sink.events.first['snapshotBytes'],
    );
    expect(
      harness.sink.events.last['bytesRead'],
      greaterThan(harness.sink.events.first['bytesRead']! as int),
    );
    final transfers = harness.peer.transfers.values.toList();
    for (var index = 0; index < harness.sink.events.length; index += 1) {
      final event = harness.sink.events[index];
      _expectSuccess(event, harness.peer.publicState);
      _expectTransfers(event, transfers[index]);
      _expectSafe(index == 0 ? before : after, event);
      expect(event['firestoreReadCount'], 3);
      expect(jsonEncode(event), isNot(contains('measurementFixture')));
    }
  });

  test('public GET still bypasses recovery observability', () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final response = await harness.request(
      'GET',
      '/v1/authority/games/$_gameId',
    );

    expect(response.status, HttpStatus.ok);
    expect(response.body, harness.peer.publicState);
    expect(harness.peer.onlyTransfer.documentReads, 2);
    expect(harness.sink.events, isEmpty);
  });

  test(
    'invalid reconnect input is rejected before capture or store access',
    () async {
      final harness = await _Harness.start();
      addTearDown(harness.close);
      final response = await harness.request(
        'POST',
        '/v1/authority/reconnect',
        <String, Object?>{'gameId': _gameId, 'observedStateVersion': -1},
      );

      _expectHttpError(
        response,
        HttpStatus.badRequest,
        'invalidObservedStateVersion',
      );
      expect(harness.peer.methods, isEmpty);
      expect(harness.sink.events, isEmpty);
    },
  );

  test('invalid identity remains outside recovery capture', () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    final response = await harness.request(
      'POST',
      '/v1/authority/reconnect',
      harness.reconnectRequest.toWireJson(),
      'invalid-private-token',
    );

    _expectHttpError(
      response,
      HttpStatus.unauthorized,
      'authenticationRejected',
    );
    expect(harness.peer.methods, isEmpty);
    expect(harness.sink.events, isEmpty);
  });
}

void _expectSuccess(Map<String, Object> event, Map<String, Object?> snapshot) {
  expect(event['operation'], 'recovery');
  expect(event['outcome'], 'success');
  expect(event['reason'], 'none');
  expect(event['schemaVersion'], 1);
  expect(event['stateVersion'], 1);
  // Independent domain encoder; production uses AuthorityPublicSnapshot's
  // canonical serializer. Neither expression measures the whole HTTP reply.
  expect(
    event['snapshotBytes'],
    utf8.encode(CanonicalDomainJson.encode(snapshot)).length,
  );
  expect(event['snapshotBytes'], greaterThan(0));
  expect(
    event.keys,
    unorderedEquals(<String>[..._baseFields, 'schemaVersion', 'stateVersion']),
  );
  _expectDefaults(event);
}

void _expectFailure(Map<String, Object> event) {
  expect(event['operation'], 'recovery');
  expect(event['outcome'], 'internalFailure');
  expect(event['reason'], 'internalError');
  expect(event['snapshotBytes'], 0);
  expect(event.keys, unorderedEquals(_baseFields));
  _expectDefaults(event);
}

void _expectDefaults(Map<String, Object> event) {
  expect(event['retryCount'], 0);
  expect(event['conflictCount'], 0);
  expect(event['firestoreWriteCount'], 0);
  expect(event['coldStart'], isFalse);
  expect(
    event['latencyMs'],
    isA<int>().having((value) => value, 'nonnegative', greaterThanOrEqualTo(0)),
  );
}

void _expectTransfers(Map<String, Object> event, _Transfer transfer) {
  expect(event['firestoreReadCount'], transfer.documentReads);
  expect(event['bytesRead'], transfer.responseBytes);
  expect(event['bytesWritten'], transfer.requestBytes);
  expect(transfer.responseBytes, greaterThan(0));
  expect(transfer.requestBytes, greaterThan(0));
}

void _expectHttpError(_Response response, int status, String code) {
  expect(response.status, status);
  expect(response.body, <String, Object?>{
    'error': <String, Object?>{'code': code},
  });
}

void _expectSafe(_Response response, Map<String, Object> event) {
  final wire = jsonEncode(response.body);
  final logged = jsonEncode(event);
  for (final secret in <String>[
    _token,
    'uid-p1',
    'uid-p2',
    'uid-outsider',
    'private-fixture-value',
    'private-error-value',
    'transaction-private',
    'seedBytes',
    'streamCounters',
    'memberUidByPlayerId',
    'memberUids',
    'Bearer',
    base64Encode(syntheticRollSeed),
  ]) {
    expect(wire, isNot(contains(secret)));
    expect(logged, isNot(contains(secret)));
  }
  for (final privateLogValue in <String>[
    _gameId,
    _commandId,
    _uncertainHash,
    'disposition',
  ]) {
    expect(logged, isNot(contains(privateLogValue)));
  }
}

final class _Harness {
  _Harness(
    this.peer,
    this.server,
    this.storeClient,
    this.sink,
    this.reconnectRequest,
  );

  static Future<_Harness> start({
    api.ReconnectDisposition disposition = api.ReconnectDisposition.upToDate,
    String uid = _uid,
    String receiptActor = _uid,
    String? receiptHash,
    bool invalidCatalog = false,
    bool privateSnapshot = false,
    String? failMethod,
    bool throwingSink = false,
    bool interleaveBatches = false,
  }) async {
    final uncertain = switch (disposition) {
      api.ReconnectDisposition.upToDate ||
      api.ReconnectDisposition.snapshotAdvanced => null,
      _ => api.UncertainCommandIdentity(
        commandId: _commandId,
        inputHashVersion: 1,
        inputHash: _uncertainHash,
      ),
    };
    final peer = await _ReadPeer.start(
      disposition: disposition,
      receiptActor: receiptActor,
      receiptHash: receiptHash,
      invalidCatalog: invalidCatalog,
      privateSnapshot: privateSnapshot,
      failMethod: failMethod,
      interleaveBatches: interleaveBatches,
    );
    final storeClient = HttpClient();
    final store = service.FirstPlayableFirestoreRestStore(
      config: service.FirstPlayableFirestoreRestConfig.emulator(
        projectId: 'demo-reconnect-observability',
        host: '127.0.0.1:${peer.server.port}',
      ),
      httpClient: storeClient,
    );
    final sink = _Sink(throwAfterWrite: throwingSink);
    final ingress = service.AuthorityHttpIngress(
      identityVerifier: _IdentityVerifier(uid),
      commandIngress: CommandIngress(
        observability: BestEffortAuthorityObservability(sink),
      ),
      executor: service.FirstPlayableAuthorityExecutor(
        store: store,
        rulesCatalogRepository:
            service.PinnedFirstPlayableRulesCatalogRepository(
              activeRulesVersion: syntheticRollCatalog().rulesVersion,
              catalogs: <RulesCatalog>[syntheticRollCatalog()],
            ),
      ),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(ingress.handle);
    return _Harness(
      peer,
      server,
      storeClient,
      sink,
      api.AuthorityReconnectRequest(
        gameId: _gameId,
        observedStateVersion: disposition == api.ReconnectDisposition.upToDate
            ? 1
            : 0,
        uncertainCommand: uncertain,
      ),
    );
  }

  final _ReadPeer peer;
  final HttpServer server;
  final HttpClient storeClient;
  final _Sink sink;
  final api.AuthorityReconnectRequest reconnectRequest;
  final HttpClient _client = HttpClient();

  Map<String, Object> get onlyEvent {
    expect(sink.events, hasLength(1));
    return sink.events.single;
  }

  Future<_Response> reconnect() =>
      request('POST', '/v1/authority/reconnect', reconnectRequest.toWireJson());

  Future<_Response> request(
    String method,
    String path, [
    Map<String, Object?>? body,
    String token = _token,
  ]) async {
    final request = await _client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return _Response(
      response.statusCode,
      jsonDecode(text) as Map<String, Object?>,
    );
  }

  Future<void> close() async {
    _client.close(force: true);
    await server.close(force: true);
    storeClient.close(force: true);
    await peer.server.close(force: true);
  }
}

final class _ReadPeer {
  _ReadPeer(
    this.server,
    this.publicState,
    this.documents,
    this.failMethod,
    this.interleaveBatches,
  ) {
    server.listen(_handle);
  }

  static Future<_ReadPeer> start({
    required api.ReconnectDisposition disposition,
    required String receiptActor,
    required String? receiptHash,
    required bool invalidCatalog,
    required bool privateSnapshot,
    required String? failMethod,
    required bool interleaveBatches,
  }) async {
    final publicState = jsonDecode(
      jsonEncode(syntheticRollState(stateVersion: 1).toJson()),
    ) as Map<String, Object?>;
    if (invalidCatalog) {
      (publicState['board']!
              as Map<String, Object?>)['boardDefinitionVersion'] =
          'unknown-private-fixture-version';
    }
    if (privateSnapshot) {
      (publicState['turnState']! as Map<String, Object?>)['token'] =
          'private-fixture-value';
    }
    final documents = <String, Map<String, Object?>>{
      'games/$_gameId': <String, Object?>{
        'schemaVersion': 1,
        'stateVersion': 1,
        'memberUids': <String>['uid-p1', 'uid-p2'],
        'publicState': publicState,
      },
      'gameSecrets/$_gameId': <String, Object?>{
        'schemaVersion': 1,
        'rngVersion': canonicalRngVersion,
        'seedBytes': Uint8List.fromList(syntheticRollSeed),
        'streamCounters': <String, int>{
          for (final stream in RngStream.values) stream.label: 0,
        },
        'memberUidByPlayerId': <String, String>{'p1': 'uid-p1', 'p2': 'uid-p2'},
      },
    };
    if (disposition == api.ReconnectDisposition.uncertainConfirmed ||
        disposition == api.ReconnectDisposition.uncertainRejected ||
        disposition == api.ReconnectDisposition.semanticCollision) {
      final rejected =
          disposition == api.ReconnectDisposition.uncertainRejected;
      documents['games/$_gameId/commands/$_commandId'] = <String, Object?>{
        'schemaVersion': 1,
        'commandId': _commandId,
        'inputHashVersion': 1,
        'inputHash':
            receiptHash ??
            (disposition == api.ReconnectDisposition.semanticCollision
                ? List<String>.filled(64, 'b').join()
                : _uncertainHash),
        'actorUid': receiptActor,
        'resultSummary': <String, Object?>{
          'commandId': _commandId,
          'status': rejected ? 'rejected' : 'accepted',
          'stateVersionBefore': rejected ? 1 : 0,
          'stateVersionAfter': 1,
          if (rejected) 'errorCode': 'staleVersion',
        },
      };
    }
    return _ReadPeer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      publicState,
      documents,
      failMethod,
      interleaveBatches,
    );
  }

  final HttpServer server;
  final Map<String, Object?> publicState;
  final Map<String, Map<String, Object?>> documents;
  final String? failMethod;
  final bool interleaveBatches;
  final methods = <String>[];
  final transfers = <String, _Transfer>{};
  final Completer<void> _batchesArrived = Completer<void>();
  int _batches = 0;

  _Transfer get onlyTransfer {
    expect(transfers, hasLength(1));
    return transfers.values.single;
  }

  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final method = request.uri.path.split(':').last;
    methods.add(method);
    late _Transfer transfer;
    Object response = <String, Object?>{};
    if (method == 'beginTransaction') {
      final transaction = 'transaction-private-ñ-🧪-${transfers.length}';
      transfer = _Transfer(readOnly: body.containsKey('options'));
      transfers[transaction] = transfer;
      response = <String, Object?>{'transaction': transaction};
    } else {
      transfer = transfers[body['transaction']]!;
      if (method == 'batchGet' && interleaveBatches) {
        _batches += 1;
        if (_batches == 2) _batchesArrived.complete();
        await _batchesArrived.future;
      }
      if (method == failMethod) {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        response = <String, Object?>{
          'error': <String, Object?>{
            'status': 'UNAVAILABLE',
            'message': 'private-error-value ñ 🧪',
          },
        };
      } else if (method == 'batchGet') {
        final names = (body['documents']! as List).cast<String>();
        transfer.documentReads += names.length;
        response = <Object?>[
          for (final name in names)
            if (documents[name.split('/documents/').last] case final fields?)
              <String, Object?>{
                'found': <String, Object?>{
                  'name': name,
                  'fields': _fields(fields),
                },
              }
            else
              <String, Object?>{'missing': name},
        ];
      } else if (method != 'rollback') {
        request.response.statusCode = HttpStatus.badRequest;
        response = <String, Object?>{
          'error': <String, Object?>{'status': 'INVALID_ARGUMENT'},
        };
      }
    }
    final encoded = utf8.encode(jsonEncode(response));
    transfer.requestBytes += bytes.length;
    transfer.responseBytes += encoded.length;
    request.response.headers.contentType = ContentType.json;
    request.response.add(encoded);
    await request.response.close();
  }
}

final class _Transfer {
  _Transfer({required this.readOnly});
  final bool readOnly;
  int requestBytes = 0;
  int responseBytes = 0;
  int documentReads = 0;
}

final class _Response {
  const _Response(this.status, this.body);
  final int status;
  final Map<String, Object?> body;
}

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

final class _IdentityVerifier implements service.AuthorityIdentityVerifier {
  const _IdentityVerifier(this.uid);
  final String uid;

  @override
  Future<service.VerifiedIdentity> verify(String token) async {
    if (token != _token) {
      throw const service.IdentityVerificationException(
        'invalidSyntheticToken',
      );
    }
    return service.VerifiedIdentity(uid: uid, authTime: DateTime.utc(2026));
  }
}

final class _Sink implements AuthorityLogSink {
  _Sink({required this.throwAfterWrite});
  final bool throwAfterWrite;
  final events = <Map<String, Object>>[];

  @override
  void write(Map<String, Object> fields) {
    events.add(fields);
    if (throwAfterWrite) throw StateError('private-fixture-value');
  }
}

const _uid = 'uid-p1';
const _gameId = 'game-vp0';
const _commandId = 'cmd-private-reconnect';
const _token = 'token-private-reconnect';
final _uncertainHash = List<String>.filled(64, 'a').join();
const _baseFields = <String>[
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
];
