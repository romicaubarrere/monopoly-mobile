import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart';
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_command_service/security/membership_authorizer.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:test/test.dart';

// Real HTTP ingress and Firestore REST adapter, with a scripted loopback peer,
// deterministic identity fake and synthetic executor. This is not Firebase
// Emulator, cryptographic identity or full production-executor evidence.
void main() {
  final cases = <({Object error, int status, String code})>[
    (
      error: const MembershipAuthorizationException('private-membership-ñ-🧪'),
      status: HttpStatus.forbidden,
      code: 'actorForbidden',
    ),
    (
      error: const api.ClientAuthorityContractViolation(
        'syntheticContractRejected',
      ),
      status: HttpStatus.badRequest,
      code: 'syntheticContractRejected',
    ),
    (
      error: StateError('private-executor-ñ-🧪'),
      status: HttpStatus.internalServerError,
      code: 'authorityUnavailable',
    ),
  ];

  for (final sample in cases) {
    for (final throwingSink in <bool>[false, true]) {
      test(
        'preserves HTTP ${sample.status} with ${throwingSink ? 'throwing' : 'healthy'} sink',
        () async {
          final peer = await _ScriptedFirestore.start();
          addTearDown(peer.close);
          final storeClient = HttpClient();
          addTearDown(() => storeClient.close(force: true));
          final store = FirstPlayableFirestoreRestStore(
            config: FirstPlayableFirestoreRestConfig.emulator(
              projectId: 'demo-failure-http-metrics',
              host: '127.0.0.1:${peer.server.port}',
            ),
            httpClient: storeClient,
          );
          final sink = _Sink(throwAfterWrite: throwingSink);
          final executor = _SyntheticExecutor(store, sample.error);
          final ingress = AuthorityHttpIngress(
            identityVerifier: const _IdentityVerifier(),
            commandIngress: CommandIngress(
              observability: BestEffortAuthorityObservability(sink),
            ),
            executor: executor,
          );
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          server.listen(ingress.handle);
          addTearDown(() => server.close(force: true));
          final client = HttpClient();
          addTearDown(() => client.close(force: true));

          final command = api.AuthorityCommandRequest.room(
            RoomCommand(
              commandId: 'cmd-private-http-metrics',
              schemaVersion: 1,
              clientInstanceId: 'client-private-http-metrics',
              type: RoomCommandType.createRoom,
              payload: const <String, Object?>{
                'presetDraft': <String, Object?>{'presetId': 'express'},
              },
            ),
          );
          final request = await client.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}/v1/authority/commands'),
          );
          request.headers.contentType = ContentType.json;
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $_bearer',
          );
          request.add(utf8.encode(jsonEncode(command.toWireJson())));
          final response = await request.close();
          final responseText = await response.transform(utf8.decoder).join();

          expect(response.statusCode, sample.status);
          expect(jsonDecode(responseText), <String, Object?>{
            'error': <String, Object?>{'code': sample.code},
          });
          expect(executor.observedError, same(sample.error));
          expect(executor.evaluations, 1);
          expect(executor.receivedUid, _uid);
          expect(executor.receivedCommandId, command.commandId);
          expect(peer.methods, <String>[
            'beginTransaction',
            'batchGet',
            'batchGet',
            'rollback',
          ]);
          expect(peer.documentReads, 4);
          expect(sink.events, hasLength(1));
          final event = sink.events.single;
          expect(event['operation'], 'roomCommand');
          expect(event['outcome'], 'internalFailure');
          expect(event['reason'], 'internalError');
          expect(event['retryCount'], 0);
          expect(event['conflictCount'], 0);
          expect(event['firestoreReadCount'], 4);
          expect(event['firestoreWriteCount'], 0);
          expect(event['bytesRead'], peer.responseBytes);
          expect(event['bytesWritten'], peer.requestBytes);
          expect(peer.responseBytes, greaterThan(0));
          expect(peer.requestBytes, greaterThan(0));
          expect(event.keys, unorderedEquals(_failureFields));
          expect(event['snapshotBytes'], 0);
          expect(event['coldStart'], isFalse);

          final logged = jsonEncode(event);
          for (final secret in <String>[
            _uid,
            _bearer,
            command.commandId,
            'client-private-http-metrics',
            'private-membership',
            'private-executor',
            'transaction-private',
            'roomSecrets',
            'seedBytes',
            'streamCounters',
            'Bearer',
            sample.error.toString(),
          ]) {
            expect(responseText, isNot(contains(secret)));
            expect(logged, isNot(contains(secret)));
          }
          // The contract code is public only in its pre-existing HTTP mapping;
          // raw or safe error text is not added to the observability allowlist.
          expect(logged, isNot(contains(sample.code)));
        },
      );
    }
  }
}

final class _SyntheticExecutor implements AuthorityHttpExecutor {
  _SyntheticExecutor(this.store, this.originalError);

  final FirstPlayableFirestoreRestStore store;
  final Object originalError;
  Object? observedError;
  String? receivedUid;
  String? receivedCommandId;
  int evaluations = 0;

  @override
  Future<AuthorityExecutionResult<api.AuthorityCommandReply>> executeCommand({
    required IngressContext context,
    required VerifiedIdentity identity,
    required api.AuthorityCommandRequest request,
  }) async {
    receivedUid = identity.uid;
    receivedCommandId = request.commandId;
    try {
      await store.transactRoomEntry(
        kind: FirstPlayableRoomEntryKind.create,
        codeHash: List<String>.filled(64, 'b').join(),
        roomId: 'new-room',
        commandId: request.commandId,
        evaluate: (_) {
          evaluations += 1;
          throw originalError;
        },
      );
    } on Object catch (error) {
      observedError = error;
      rethrow;
    }
    throw StateError('The synthetic evaluator must fail.');
  }

  @override
  Future<api.AuthorityReconnectReply> reconnect({
    required IngressContext context,
    required VerifiedIdentity identity,
    required api.AuthorityReconnectRequest request,
  }) async => throw UnsupportedError('Unused synthetic route.');

  @override
  Future<api.AuthorityPublicSnapshot> readPublicGame({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String gameId,
  }) async => throw UnsupportedError('Unused synthetic route.');

  @override
  Future<api.AuthorityPublicRoomSnapshot> readPublicRoom({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String roomId,
  }) async => throw UnsupportedError('Unused synthetic route.');
}

final class _ScriptedFirestore {
  _ScriptedFirestore(this.server) {
    server.listen(_handle);
  }

  static Future<_ScriptedFirestore> start() async => _ScriptedFirestore(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  final HttpServer server;
  final methods = <String>[];
  int documentReads = 0;
  int requestBytes = 0;
  int responseBytes = 0;

  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    requestBytes += bytes.length;
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final method = request.uri.path.split(':').last;
    methods.add(method);
    Object response;
    switch (method) {
      case 'beginTransaction':
        response = <String, Object?>{'transaction': 'transaction-private-ñ-🧪'};
      case 'batchGet':
        final documents = (body['documents']! as List).cast<String>();
        documentReads += documents.length;
        response = <Object?>[
          for (final document in documents)
            <String, Object?>{'missing': document},
        ];
      case 'rollback':
        response = <String, Object?>{};
      default:
        request.response.statusCode = HttpStatus.badRequest;
        response = <String, Object?>{
          'error': <String, Object?>{'status': 'INVALID_ARGUMENT'},
        };
    }
    final encoded = utf8.encode(jsonEncode(response));
    responseBytes += encoded.length;
    request.response.headers.contentType = ContentType.json;
    request.response.add(encoded);
    await request.response.close();
  }

  Future<void> close() => server.close(force: true);
}

final class _IdentityVerifier implements AuthorityIdentityVerifier {
  const _IdentityVerifier();

  @override
  Future<VerifiedIdentity> verify(String token) async {
    if (token != _bearer) {
      throw const IdentityVerificationException('unexpectedSyntheticToken');
    }
    return VerifiedIdentity(uid: _uid, authTime: DateTime.utc(2026));
  }
}

final class _Sink implements AuthorityLogSink {
  _Sink({required this.throwAfterWrite});

  final bool throwAfterWrite;
  final events = <Map<String, Object>>[];

  @override
  void write(Map<String, Object> fields) {
    events.add(fields);
    if (throwAfterWrite) throw StateError('private-sink-failure');
  }
}

const _uid = 'uid-private-http-metrics';
const _bearer = 'synthetic-private-bearer-token';
const _failureFields = <String>[
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
