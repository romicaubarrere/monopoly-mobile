import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_command_service/http/authority_http_ingress.dart';
import 'package:board_command_service/ingress/command_ingress.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_command_service/security/firebase_identity_verifier.dart';
import 'package:board_command_service/security/membership_authorizer.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

// Real numeric-loopback HTTP ingress, but deliberately synthetic identity,
// executor side effects and counters. This is not cryptographic verification,
// an Engine transition, Firestore commit/atomicity or production cost evidence.
void main() {
  for (final family in AuthorityCommandFamily.values) {
    for (final fault in _Fault.values) {
      test(
        '${family.name} success survives ${fault.name} diagnostics',
        () async {
          final harness = await _Harness.start(fault: fault);
          final command = _command(family);
          final response = await harness.send(command.toWireJson());

          expect(response.status, HttpStatus.ok);
          expect(response.body, <String, Object?>{
            'commandId': command.commandId,
            'status': 'accepted',
            'versionBefore': 0,
            'versionAfter': 1,
            'publicResult': <String, Object?>{'syntheticVersion': 1},
          });
          _expectExecutedOnce(harness, command);
          expect(harness.executor.syntheticVersion, 1);
          expect(
            harness.sink.events.where(
              (event) => event['outcome'] == 'internalFailure',
            ),
            isEmpty,
            reason:
                'A diagnostic fault must not manufacture an authority failure.',
          );
          if (fault == _Fault.healthy || fault == _Fault.sink) {
            expect(harness.sink.events, hasLength(1));
            expect(harness.sink.events.single, <String, Object>{
              'operation': '${family.name}Command',
              'outcome': 'success',
              'reason': 'none',
              'latencyMs': 7,
              'retryCount': 0,
              'conflictCount': 0,
              'firestoreReadCount': 3,
              'firestoreWriteCount': 1,
              'bytesRead': 17,
              'bytesWritten': 19,
              'snapshotBytes': 0,
              'coldStart': false,
              'schemaVersion': 1,
              'stateVersion': 1,
            });
          } else {
            expect(harness.sink.events, isEmpty);
          }
          _expectNoPrivateDiagnostics(response, harness);
        },
      );
    }
  }

  final errors = <({Object error, int status, String code})>[
    (
      error: const MembershipAuthorizationException(
        'synthetic-private-membership',
      ),
      status: HttpStatus.forbidden,
      code: 'actorForbidden',
    ),
    (
      error: const ClientAuthorityContractViolation(
        'syntheticContractRejected',
      ),
      status: HttpStatus.badRequest,
      code: 'syntheticContractRejected',
    ),
    (
      error: StateError('synthetic-private-executor'),
      status: HttpStatus.internalServerError,
      code: 'authorityUnavailable',
    ),
  ];
  for (final sample in errors) {
    for (final fault in <_Fault>[
      _Fault.healthy,
      _Fault.startClock,
      _Fault.endClock,
      _Fault.sink,
    ]) {
      test('executor HTTP ${sample.status} survives ${fault.name}', () async {
        final harness = await _Harness.start(fault: fault, error: sample.error);
        final command = _command(AuthorityCommandFamily.game);
        final response = await harness.send(command.toWireJson());

        expect(response.status, sample.status);
        expect(response.body, <String, Object?>{
          'error': <String, Object?>{'code': sample.code},
        });
        _expectExecutedOnce(harness, command);
        expect(harness.executor.syntheticVersion, 0);
        if (fault == _Fault.healthy || fault == _Fault.sink) {
          expect(harness.sink.events, hasLength(1));
          expect(harness.sink.events.single, <String, Object>{
            'operation': 'gameCommand',
            'outcome': 'internalFailure',
            'reason': 'internalError',
            'latencyMs': 7,
            'retryCount': 0,
            'conflictCount': 0,
            'firestoreReadCount': 2,
            'firestoreWriteCount': 0,
            'bytesRead': 11,
            'bytesWritten': 13,
            'snapshotBytes': 0,
            'coldStart': false,
          });
        } else {
          expect(harness.sink.events, isEmpty);
        }
        _expectNoPrivateDiagnostics(response, harness);
      });
    }
  }

  for (final fault in <_Fault>[
    _Fault.healthy,
    _Fault.startClock,
    _Fault.endClock,
  ]) {
    test('private reply stays rejected with ${fault.name}', () async {
      final harness = await _Harness.start(fault: fault, privateResult: true);
      final command = _command(AuthorityCommandFamily.room);
      final response = await harness.send(command.toWireJson());

      // The actual reply constructor's recursive public-material guard throws
      // inside the synthetic executor; diagnostics must not swallow that error.
      expect(response.status, HttpStatus.badRequest);
      expect(response.body, <String, Object?>{
        'error': <String, Object?>{'code': 'privateMaterialForbidden'},
      });
      _expectExecutedOnce(harness, command);
      expect(harness.executor.syntheticVersion, 0);
      expect(
        harness.sink.events.where((event) => event['outcome'] == 'success'),
        isEmpty,
      );
      _expectNoPrivateDiagnostics(response, harness);
    });
  }

  test(
    'rejected identity never reaches executor or diagnostic clock',
    () async {
      final harness = await _Harness.start(fault: _Fault.startClock);
      final response = await harness.send(
        _command(AuthorityCommandFamily.game).toWireJson(),
        bearer: 'synthetic-wrong-token',
      );

      expect(response.status, HttpStatus.unauthorized);
      expect(response.body, <String, Object?>{
        'error': <String, Object?>{'code': 'authenticationRejected'},
      });
      expect(harness.executor.executions, 0);
      expect(harness.clock.calls, 0);
      expect(harness.sink.events, isEmpty);
      expect(harness.authorityClockCalls, 1);
      _expectNoPrivateDiagnostics(response, harness);
    },
  );

  test('invalid command still fails before diagnostic execution', () async {
    final harness = await _Harness.start(fault: _Fault.startClock);
    final wire = _command(AuthorityCommandFamily.game).toWireJson();
    wire['inputHashVersion'] = 2;
    final response = await harness.send(wire);

    expect(response.status, HttpStatus.badRequest);
    expect(response.body, <String, Object?>{
      'error': <String, Object?>{'code': 'unsupportedInputHashVersion'},
    });
    expect(harness.executor.executions, 0);
    expect(harness.clock.calls, 0);
    expect(harness.sink.events, isEmpty);
    expect(harness.authorityClockCalls, 1);
    _expectNoPrivateDiagnostics(response, harness);
  });
}

enum _Fault { healthy, startClock, endClock, invalidMetric, sink }

void _expectExecutedOnce(_Harness harness, AuthorityCommandRequest command) {
  expect(harness.executor.executions, 1);
  expect(harness.executor.receivedContext!.requestReceivedAt, _receivedAt);
  expect(harness.authorityClockCalls, 1);
  expect(harness.executor.receivedIdentity!.uid, _uid);
  expect(harness.executor.receivedRequest!.toWireJson(), command.toWireJson());
}

void _expectNoPrivateDiagnostics(_Response response, _Harness harness) {
  final diagnostics = jsonEncode(harness.sink.events);
  final body = jsonEncode(response.body);
  for (final private in <String>[
    _uid,
    _bearer,
    'synthetic-private-clock',
    'synthetic-private-sink',
    'synthetic-private-membership',
    'synthetic-private-executor',
    'synthetic-private-value',
    'synthetic-wrong-token',
  ]) {
    expect(body, isNot(contains(private)));
    expect(diagnostics, isNot(contains(private)));
  }
  expect(diagnostics, isNot(contains('synthetic-command')));
  expect(diagnostics, isNot(contains('synthetic-client')));
}

AuthorityCommandRequest _command(AuthorityCommandFamily family) =>
    switch (family) {
      AuthorityCommandFamily.room => AuthorityCommandRequest.room(
        RoomCommand(
          commandId: 'synthetic-command-room',
          schemaVersion: 1,
          clientInstanceId: 'synthetic-client',
          type: RoomCommandType.createRoom,
          payload: const <String, Object?>{
            'presetDraft': <String, Object?>{'presetId': 'express'},
          },
        ),
      ),
      AuthorityCommandFamily.game => AuthorityCommandRequest.game(
        GameCommand(
          commandId: 'synthetic-command-game',
          schemaVersion: 1,
          clientInstanceId: 'synthetic-client',
          expectedStateVersion: 0,
          gameId: 'synthetic-game',
          actorPlayerId: 'synthetic-player',
          type: GameCommandType.rollDice,
          payload: const <String, Object?>{},
        ),
      ),
    };

final class _Harness {
  _Harness(this.executor, this.sink, this.clock);

  final _SyntheticExecutor executor;
  final _Sink sink;
  final _Clock clock;
  final HttpClient client = HttpClient();
  late final HttpServer server;
  int authorityClockCalls = 0;

  static Future<_Harness> start({
    required _Fault fault,
    Object? error,
    bool privateResult = false,
  }) async {
    final harness = _Harness(
      _SyntheticExecutor(fault, error: error, privateResult: privateResult),
      _Sink(fault == _Fault.sink),
      _Clock(fault),
    );
    final ingress = AuthorityHttpIngress(
      identityVerifier: const _SyntheticIdentityVerifier(),
      commandIngress: CommandIngress(
        observability: BestEffortAuthorityObservability(harness.sink),
        now: harness.clock.now,
      ),
      executor: harness.executor,
      now: () {
        harness.authorityClockCalls += 1;
        return _receivedAt;
      },
    );
    harness.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    harness.server.listen(ingress.handle);
    addTearDown(() async {
      harness.client.close(force: true);
      await harness.server.close(force: true);
    });
    return harness;
  }

  Future<_Response> send(
    Map<String, Object?> wire, {
    String bearer = _bearer,
  }) async {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/v1/authority/commands'),
    );
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
    request.add(utf8.encode(jsonEncode(wire)));
    final response = await request.close();
    final body = jsonDecode(await response.transform(utf8.decoder).join());
    return _Response(response.statusCode, body as Map<String, Object?>);
  }
}

final class _Response {
  const _Response(this.status, this.body);

  final int status;
  final Map<String, Object?> body;
}

final class _Clock {
  _Clock(this.fault);

  final _Fault fault;
  int calls = 0;

  DateTime now() {
    calls += 1;
    if (fault == _Fault.startClock && calls == 1 ||
        fault == _Fault.endClock && calls == 2) {
      throw StateError('synthetic-private-clock');
    }
    // Deliberately distinct from the authority request time.
    return DateTime.utc(2027).add(Duration(milliseconds: calls * 7));
  }
}

final class _Sink implements AuthorityLogSink {
  _Sink(this.throwOnWrite);

  final bool throwOnWrite;
  final events = <Map<String, Object>>[];

  @override
  void write(Map<String, Object> fields) {
    events.add(fields);
    if (throwOnWrite) throw StateError('synthetic-private-sink');
  }
}

final class _SyntheticIdentityVerifier implements AuthorityIdentityVerifier {
  const _SyntheticIdentityVerifier();

  @override
  Future<VerifiedIdentity> verify(String token) async {
    if (token != _bearer) {
      throw const IdentityVerificationException('synthetic-private-identity');
    }
    return VerifiedIdentity(uid: _uid, authTime: _receivedAt);
  }
}

final class _SyntheticExecutor implements AuthorityHttpExecutor {
  _SyntheticExecutor(this.fault, {this.error, required this.privateResult});

  final _Fault fault;
  final Object? error;
  final bool privateResult;
  int executions = 0;
  int syntheticVersion = 0;
  IngressContext? receivedContext;
  VerifiedIdentity? receivedIdentity;
  AuthorityCommandRequest? receivedRequest;

  @override
  Future<AuthorityExecutionResult<AuthorityCommandReply>> executeCommand({
    required IngressContext context,
    required VerifiedIdentity identity,
    required AuthorityCommandRequest request,
  }) async {
    executions += 1;
    receivedContext = context;
    receivedIdentity = identity;
    receivedRequest = request;
    await Future<void>.value();
    AuthorityExecutionMetricsCapture.record(
      const AuthorityExecutionMetrics(
        firestoreReadCount: 2,
        bytesRead: 11,
        bytesWritten: 13,
      ),
    );
    if (error != null) throw error!;
    final reply = AuthorityCommandReply(
      commandId: request.commandId,
      status: AuthorityCommandStatus.accepted,
      versionBefore: 0,
      versionAfter: 1,
      publicResult: <String, Object?>{
        if (privateResult)
          'nested': <Object?>[
            <String, Object?>{'ToKeN': 'synthetic-private-value'},
          ]
        else
          'syntheticVersion': 1,
      },
    );
    syntheticVersion += 1;
    return AuthorityExecutionResult(
      value: reply,
      outcome: AuthorityOutcome.success,
      reason: AuthorityReason.none,
      metrics: AuthorityExecutionMetrics(
        firestoreReadCount: 3,
        firestoreWriteCount: 1,
        bytesRead: 17,
        bytesWritten: 19,
        snapshotBytes: fault == _Fault.invalidMetric ? -1 : 0,
        schemaVersion: 1,
        stateVersion: 1,
      ),
    );
  }

  @override
  Future<AuthorityReconnectReply> reconnect({
    required IngressContext context,
    required VerifiedIdentity identity,
    required AuthorityReconnectRequest request,
  }) async => throw UnsupportedError('Unused synthetic route');

  @override
  Future<AuthorityPublicSnapshot> readPublicGame({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String gameId,
  }) async => throw UnsupportedError('Unused synthetic route');

  @override
  Future<AuthorityPublicRoomSnapshot> readPublicRoom({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String roomId,
  }) async => throw UnsupportedError('Unused synthetic route');
}

final _receivedAt = DateTime.utc(2026, 9, 8, 17, 3, 11, 123);
const _uid = 'synthetic-private-actor';
const _bearer = 'synthetic-private-bearer';
