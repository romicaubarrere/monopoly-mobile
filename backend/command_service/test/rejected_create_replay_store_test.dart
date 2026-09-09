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

// Actual material derivation, executor, persistence codec and REST store. The
// loopback peer retains their encoded documents and measures UTF-8 I/O. The
// occupied-code case explicitly injects a synthetic collision; it does not
// claim an HMAC collision, real Firestore atomicity, HTTP ingress or cloud proof.
void main() {
  for (final outcome in [_Initial.invalidPreset, _Initial.occupiedCode]) {
    test(
      '${outcome.name} replay preserves the rejected result without a code',
      () async {
        final scenario = await _Scenario.start(outcome);
        final before = scenario.peer.documentSnapshot;
        final receipt = scenario.peer.receipt;
        _same(
          receipt['resultSummary']! as Map<String, Object?>,
          scenario.first.value.publicResult,
        );
        expect(
          scenario.first.value.publicResult.containsKey('roomCode'),
          isFalse,
        );
        expect(scenario.first.value.isRejectedOutcome, isTrue);
        scenario.now = scenario.now.add(const Duration(minutes: 1));

        final replay = await scenario.measured(scenario.request, writes: 0);

        expect(replay.value.status, api.AuthorityCommandStatus.duplicate);
        expect(replay.outcome, AuthorityOutcome.duplicate);
        expect(replay.reason, AuthorityReason.duplicateCommand);
        expect(replay.value.isRejectedOutcome, isTrue);
        expect(replay.value.errorCode, scenario.first.value.errorCode);
        expect(replay.value.versionBefore, scenario.first.value.versionBefore);
        expect(replay.value.versionAfter, scenario.first.value.versionAfter);
        expect(replay.value.snapshot, isNull);
        expect(scenario.peer.documentSnapshot == before, isTrue);
        expect(scenario.peer.commits, 0);
        expect(scenario.peer.rollbacks, 1);
        expect(replay.value.publicResult.containsKey('roomCode'), isFalse);
        _same(replay.value.publicResult, scenario.first.value.publicResult);
        _same(scenario.peer.receipt, receipt);
      },
    );
  }

  test(
    'accepted Create replay still restores its transient code only',
    () async {
      final scenario = await _Scenario.start(_Initial.accepted);
      final before = scenario.peer.documentSnapshot;
      final receipt = scenario.peer.receipt;
      final durableResult = receipt['resultSummary']! as Map<String, Object?>;
      final firstResult = {...scenario.first.value.publicResult}
        ..remove('roomCode');
      _same(durableResult, firstResult);
      expect(durableResult.containsKey('roomCode'), isFalse);
      expect(
        scenario.first.value.publicResult['roomCode'] ==
            scenario.targetMaterial.roomCode,
        isTrue,
      );
      scenario.now = scenario.now.add(const Duration(minutes: 1));

      final replay = await scenario.measured(scenario.request, writes: 0);

      expect(replay.value.status, api.AuthorityCommandStatus.duplicate);
      expect(replay.outcome, AuthorityOutcome.duplicate);
      expect(replay.value.isRejectedOutcome, isFalse);
      expect(replay.value.errorCode, isNull);
      expect(replay.value.versionBefore, 0);
      expect(replay.value.versionAfter, 1);
      expect(replay.value.snapshot, isNull);
      _same(replay.value.publicResult, scenario.first.value.publicResult);
      _same(scenario.peer.receipt, receipt);
      expect(scenario.peer.documentSnapshot == before, isTrue);
      expect(scenario.peer.commits, 0);
      expect(scenario.peer.rollbacks, 1);
    },
  );

  for (final outcome in [_Initial.accepted, _Initial.invalidPreset]) {
    for (final mismatch in _Mismatch.values) {
      test(
        '${outcome.name} receipt rejects ${mismatch.name} collision without a result',
        () async {
          final scenario = await _Scenario.start(outcome);
          final before = scenario.peer.documentSnapshot;
          var request = scenario.request;
          if (mismatch == _Mismatch.inputHash) {
            request = _request(
              _commandId,
              validPreset: outcome == _Initial.invalidPreset,
            );
            expect(request.inputHash != scenario.request.inputHash, isTrue);
          } else if (mismatch == _Mismatch.materialHash) {
            final alternate = await scenario.factory.roomEntry(
              _request('synthetic-other-code-source').asRoomCommand,
              scenario.now,
            );
            expect(
              alternate.codeHash != scenario.targetMaterial.codeHash,
              isTrue,
            );
            scenario.replacementCodeMaterial = alternate;
          }

          final collision = await scenario.measured(
            request,
            uid: mismatch == _Mismatch.actor ? _otherUid : _actorUid,
            writes: 0,
          );

          expect(collision.value.status, api.AuthorityCommandStatus.rejected);
          expect(collision.outcome, AuthorityOutcome.collision);
          expect(collision.reason, AuthorityReason.commandIdCollision);
          expect(collision.value.errorCode, 'commandIdCollision');
          expect(collision.value.isRejectedOutcome, isTrue);
          expect(collision.value.snapshot, isNull);
          expect(
            collision.value.publicResult.keys.any(
              {'roomCode', 'roomSnapshot', 'actorPlayerId', 'roomId'}.contains,
            ),
            isFalse,
          );
          expect(scenario.peer.documentSnapshot == before, isTrue);
          expect(scenario.peer.commits, 0);
          expect(scenario.peer.rollbacks, 1);
        },
      );
    }
  }

  for (final corruption in _Corruption.values) {
    test('corrupt rejected receipt fails closed: ${corruption.name}', () async {
      final scenario = await _Scenario.start(_Initial.invalidPreset);
      final fields = scenario.peer.documents['roomCommands/$_commandId']!;
      final summary =
          (fields['resultSummary']! as Map<String, Object?>)['mapValue']!
              as Map<String, Object?>;
      final resultFields = summary['fields']! as Map<String, Object?>;
      late final Matcher errorMatcher;
      switch (corruption) {
        case _Corruption.commandId:
          fields['commandId'] = {'stringValue': 'synthetic-other-command'};
          errorMatcher = isA<FirstPlayableFirestoreStoreViolation>().having(
            (error) => error.code,
            'safe code',
            'receiptIdentityMismatch',
          );
        case _Corruption.missingRejectionCode:
          resultFields.remove('errorCode');
          errorMatcher = isA<AuthorityReconnectViolation>().having(
            (error) => error.code,
            'safe code',
            'invalidDurableCommandResult',
          );
        case _Corruption.privateResult:
          resultFields['nested'] = {
            'mapValue': {
              'fields': {
                'seed': {'stringValue': 'synthetic-private-marker'},
              },
            },
          };
          errorMatcher = isA<api.ClientAuthorityContractViolation>().having(
            (error) => error.code,
            'safe code',
            'privateMaterialForbidden',
          );
      }
      final before = scenario.peer.documentSnapshot;
      scenario.peer.resetCounters();
      final capture = AuthorityExecutionMetricsCapture();

      await expectLater(
        capture.run(() => scenario.execute(scenario.request)),
        throwsA(errorMatcher),
      );

      _metrics(capture.metrics, scenario.peer, writes: 0);
      expect(capture.metrics.schemaVersion, isNull);
      expect(capture.metrics.stateVersion, isNull);
      expect(scenario.peer.documentSnapshot == before, isTrue);
      expect(scenario.peer.commits, 0);
      expect(scenario.peer.rollbacks, 1);
    });
  }
}

enum _Initial { accepted, invalidPreset, occupiedCode }

enum _Mismatch { actor, inputHash, materialHash }

enum _Corruption { commandId, missingRejectionCode, privateResult }

final class _Scenario {
  _Scenario(this.peer, this.outcome) {
    final catalog = syntheticRollCatalog();
    executor = FirstPlayableAuthorityExecutor(
      store: peer.store,
      rulesCatalogRepository: PinnedFirstPlayableRulesCatalogRepository(
        activeRulesVersion: catalog.rulesVersion,
        catalogs: [catalog],
      ),
      roomEntryMaterialFactory: (command, receivedAt) async {
        final candidate = await factory.roomEntry(command, receivedAt);
        var effective = candidate;
        if (command.commandId == _commandId) {
          targetCandidate = candidate;
          // Preserve this command's candidate room/player/expiry. Replacing
          // only the code/hash pair deliberately scripts locator contention.
          final replacement = replacementCodeMaterial;
          if (replacement != null) {
            effective = FirstPlayableRoomEntryMaterial(
              kind: candidate.kind,
              roomCode: replacement.roomCode,
              codeHash: replacement.codeHash,
              playerId: candidate.playerId,
              roomId: candidate.roomId,
              expiresAt: candidate.expiresAt,
            );
          }
          targetMaterial = effective;
        }
        lastMaterial = effective;
        return effective;
      },
    );
  }

  static Future<_Scenario> start(_Initial outcome) async {
    final peer = await _Peer.start();
    addTearDown(peer.close);
    final scenario = _Scenario(peer, outcome);
    String? occupiedSnapshot;
    if (outcome == _Initial.occupiedCode) {
      final occupying = await scenario.measured(
        _request('synthetic-occupying-create'),
        writes: 4,
      );
      expect(occupying.value.status, api.AuthorityCommandStatus.accepted);
      scenario.replacementCodeMaterial = scenario.lastMaterial;
      occupiedSnapshot = peer.documentSnapshot;
    }
    final existingPaths = peer.documents.keys.toSet();
    scenario.first = await scenario.measured(
      scenario.request,
      writes: outcome == _Initial.accepted ? 4 : 1,
    );
    final accepted = outcome == _Initial.accepted;
    expect(
      scenario.first.value.status,
      accepted
          ? api.AuthorityCommandStatus.accepted
          : api.AuthorityCommandStatus.rejected,
    );
    expect(scenario.first.value.versionBefore, 0);
    expect(scenario.first.value.versionAfter, accepted ? 1 : 0);
    expect(scenario.first.value.isRejectedOutcome, !accepted);
    if (!accepted) {
      expect(
        scenario.first.value.errorCode,
        outcome == _Initial.invalidPreset
            ? 'invalidPresetDraft'
            : 'roomCodeUnavailable',
      );
      expect(peer.documents.keys.toSet().difference(existingPaths), {
        'roomCommands/$_commandId',
      });
      expect(
        peer.documents.containsKey('rooms/${scenario.targetMaterial.roomId}'),
        isFalse,
      );
      expect(
        peer.documents.containsKey(
          'roomSecrets/${scenario.targetMaterial.roomId}',
        ),
        isFalse,
      );
    }
    if (occupiedSnapshot != null) {
      expect(
        CanonicalDomainJson.encode({
              for (final path in existingPaths) path: peer.documents[path],
            }) ==
            occupiedSnapshot,
        isTrue,
      );
      expect(
        scenario.targetMaterial.roomId == scenario.targetCandidate.roomId,
        isTrue,
      );
      expect(
        scenario.targetMaterial.playerId == scenario.targetCandidate.playerId,
        isTrue,
      );
      expect(
        scenario.targetMaterial.expiresAt == scenario.targetCandidate.expiresAt,
        isTrue,
      );
      expect(
        scenario.targetMaterial.roomId !=
            scenario.replacementCodeMaterial!.roomId,
        isTrue,
      );
      expect(
        scenario.targetMaterial.codeHash ==
            scenario.replacementCodeMaterial!.codeHash,
        isTrue,
      );
    }
    final receipt = peer.receipt;
    expect(receipt['inputHash'] == scenario.request.inputHash, isTrue);
    expect(receipt['inputHashVersion'], scenario.request.inputHashVersion);
    expect(
      receipt['roomEntryCodeHash'] == scenario.targetMaterial.codeHash,
      isTrue,
    );
    expect(receipt['actorUid'] == _actorUid, isTrue);
    expect(
      peer.documentSnapshot.contains(scenario.targetMaterial.roomCode),
      isFalse,
    );
    return scenario;
  }

  final _Peer peer;
  final _Initial outcome;
  final factory = FirstPlayableAuthorityMaterialFactory(
    key: List.generate(32, (index) => index),
    roomCodeTtl: const Duration(minutes: 10),
  );
  late final FirstPlayableAuthorityExecutor executor;
  late AuthorityExecutionResult<api.AuthorityCommandReply> first;
  late FirstPlayableRoomEntryMaterial lastMaterial;
  late FirstPlayableRoomEntryMaterial targetCandidate;
  late FirstPlayableRoomEntryMaterial targetMaterial;
  FirstPlayableRoomEntryMaterial? replacementCodeMaterial;
  DateTime now = DateTime.utc(2026, 9, 9, 1);

  api.AuthorityCommandRequest get request =>
      _request(_commandId, validPreset: outcome != _Initial.invalidPreset);

  Future<AuthorityExecutionResult<api.AuthorityCommandReply>> execute(
    api.AuthorityCommandRequest request, {
    String uid = _actorUid,
  }) => executor.executeCommand(
    context: IngressContext(requestReceivedAt: now),
    identity: VerifiedIdentity(uid: uid, authTime: now),
    request: request,
  );

  Future<AuthorityExecutionResult<api.AuthorityCommandReply>> measured(
    api.AuthorityCommandRequest request, {
    required int writes,
    String uid = _actorUid,
  }) async {
    peer.resetCounters();
    final capture = AuthorityExecutionMetricsCapture();
    final result = await capture.run(() => execute(request, uid: uid));
    for (final metrics in [result.metrics, capture.metrics]) {
      _metrics(metrics, peer, writes: writes);
    }
    expect(result.metrics.schemaVersion, 1);
    expect(result.metrics.stateVersion, result.value.versionAfter);
    expect(capture.metrics.schemaVersion, isNull);
    expect(capture.metrics.stateVersion, isNull);
    final reply = CanonicalDomainJson.encode(result.value.toWireJson());
    expect(reply.contains(_actorUid) || reply.contains(_otherUid), isFalse);
    expect(
      peer.requestedDocuments[0].join('|') ==
          'roomCodes/${lastMaterial.codeHash}|roomCommands/${request.commandId}',
      isTrue,
    );
    expect(
      peer.requestedDocuments[1].join('|') ==
          'rooms/${lastMaterial.roomId}|roomSecrets/${lastMaterial.roomId}',
      isTrue,
    );
    return result;
  }
}

api.AuthorityCommandRequest _request(
  String commandId, {
  bool validPreset = true,
}) => api.AuthorityCommandRequest.room(
  RoomCommand(
    commandId: commandId,
    schemaVersion: 1,
    clientInstanceId: 'synthetic-create-replay-client',
    type: RoomCommandType.createRoom,
    payload: {
      'presetDraft': <String, Object?>{if (validPreset) 'presetId': 'express'},
    },
  ),
);

void _same(Map<String, Object?> actual, Map<String, Object?> expected) =>
    expect(
      CanonicalDomainJson.encode(actual) ==
          CanonicalDomainJson.encode(expected),
      isTrue,
      reason: 'equality without printing private documents or transient codes',
    );

void _metrics(
  AuthorityExecutionMetrics metrics,
  _Peer peer, {
  required int writes,
}) {
  expect(metrics.retryCount, 0);
  expect(metrics.conflictCount, 0);
  expect(metrics.firestoreReadCount, 4);
  expect(peer.requestedDocuments, hasLength(2));
  expect(peer.requestedDocuments.expand((batch) => batch), hasLength(4));
  expect(metrics.firestoreWriteCount, writes);
  expect(peer.confirmedWrites, writes);
  expect(metrics.bytesRead, peer.responseBytes);
  expect(metrics.bytesWritten, peer.requestBytes);
  expect(metrics.bytesRead, greaterThan(0));
  expect(metrics.bytesWritten, greaterThan(0));
  expect(metrics.snapshotBytes, 0);
  expect(metrics.coldStart, isFalse);
  expect(peer.begins, 1);
}

final class _Peer {
  _Peer(this.server) {
    store = FirstPlayableFirestoreRestStore(
      config: FirstPlayableFirestoreRestConfig.emulator(
        projectId: 'demo-rejected-create-replay',
        host: '127.0.0.1:${server.port}',
      ),
      httpClient: client,
    );
    server.listen(_handle);
  }

  static Future<_Peer> start() async =>
      _Peer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer server;
  final HttpClient client = HttpClient();
  late final FirstPlayableFirestoreRestStore store;
  final documents = <String, Map<String, Object?>>{};
  final requestedDocuments = <List<String>>[];
  int begins = 0;
  int commits = 0;
  int rollbacks = 0;
  int confirmedWrites = 0;
  int requestBytes = 0;
  int responseBytes = 0;

  String get documentSnapshot => CanonicalDomainJson.encode(documents);
  Map<String, Object?> get receipt => {
    for (final entry in documents['roomCommands/$_commandId']!.entries)
      entry.key: _decodeValue(entry.value),
  };

  void resetCounters() {
    begins = 0;
    commits = 0;
    rollbacks = 0;
    confirmedWrites = 0;
    requestBytes = 0;
    responseBytes = 0;
    requestedDocuments.clear();
  }

  Future<void> _handle(HttpRequest request) async {
    final bytes = await request.fold<List<int>>(
      [],
      (all, chunk) => all..addAll(chunk),
    );
    requestBytes += bytes.length;
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    Object response = <String, Object?>{};
    var status = HttpStatus.ok;
    switch (request.uri.path.split(':').last) {
      case 'beginTransaction':
        response = {'transaction': 'synthetic-create-replay-${++begins}'};
      case 'batchGet':
        final names = (body['documents']! as List).cast<String>();
        requestedDocuments.add([
          for (final name in names) name.split('/documents/').last,
        ]);
        response = [
          for (final name in names)
            if (documents[name.split('/documents/').last] case final fields?)
              {
                'found': {'name': name, 'fields': fields},
              }
            else
              {'missing': name},
        ];
      case 'commit':
        commits += 1;
        final writes = (body['writes']! as List).cast<Map<String, Object?>>();
        for (final write in writes) {
          // Create and its rejections only use replacement writes. Fail closed
          // if a future adapter change asks this bounded peer to merge/delete.
          if (write.containsKey('updateMask') ||
              write['update'] is! Map<String, Object?>) {
            throw StateError('unsupportedSyntheticCreateWrite');
          }
          final update = write['update']! as Map<String, Object?>;
          final path = (update['name']! as String).split('/documents/').last;
          documents[path] = {...update['fields']! as Map<String, Object?>};
        }
        confirmedWrites += writes.length;
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

Object? _decodeValue(Object? encoded) {
  final value = encoded! as Map<String, Object?>;
  if (value.containsKey('stringValue')) return value['stringValue'];
  if (value.containsKey('integerValue')) {
    return int.parse(value['integerValue']! as String);
  }
  if (value.containsKey('booleanValue')) return value['booleanValue'];
  if (value.containsKey('timestampValue')) return value['timestampValue'];
  if (value.containsKey('nullValue')) return null;
  if (value['mapValue'] case final Map<String, Object?> map) {
    final fields = map['fields']! as Map<String, Object?>;
    return <String, Object?>{
      for (final entry in fields.entries) entry.key: _decodeValue(entry.value),
    };
  }
  if (value['arrayValue'] case final Map<String, Object?> array) {
    return (array['values']! as List).map(_decodeValue).toList();
  }
  throw StateError('unsupportedSyntheticCreateField');
}

const _commandId = 'synthetic-create-replay';
const _actorUid = 'synthetic-create-actor-ñ';
const _otherUid = 'synthetic-other-actor-🌿';
