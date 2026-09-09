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

// Real material factory, executor, codec and REST store over a scripted numeric
// loopback peer. All operations share the actual encoded room documents. This
// proves adapter behavior, not Firestore concurrency, cloud or UI behavior.
void main() {
  for (final readyCount in [0, 1, 3]) {
    test(
      'Join advances persisted version after $readyCount Ready commands',
      () async {
        final scenario = await _Scenario.start();
        await scenario.readyTimes(readyCount);
        final roomBefore = scenario.room;
        final privateBefore = scenario.privateRoom;
        final locatorBefore = scenario.peer.locatorSnapshot;

        final joined = await scenario.measured(
          scenario.joinRequest,
          uid: _guestUid,
          reads: 4,
          writes: 3,
        );

        _acceptedJoin(scenario, joined, roomBefore, privateBefore);
        expect(joined.value.versionBefore, 1 + readyCount);
        expect(joined.value.versionAfter, 2 + readyCount);
        expect(scenario.peer.locatorSnapshot == locatorBefore, isTrue);
        expect(scenario.materialCalls, 1);
        expect(scenario.peer.commits, 1);
        expect(scenario.peer.rollbacks, 0);
        _entryReads(scenario, scenario.joinRequest);
      },
    );
  }

  for (final conflicts in [1, 2]) {
    test(
      'Join after Ready commits once through $conflicts conflicts',
      () async {
        final scenario = await _Scenario.start();
        await scenario.readyTimes(1);
        final roomBefore = scenario.room;
        final privateBefore = scenario.privateRoom;
        final locatorBefore = scenario.peer.locatorSnapshot;
        scenario.peer.conflicts = conflicts;

        final joined = await scenario.measured(
          scenario.joinRequest,
          uid: _guestUid,
          reads: 4 * (conflicts + 1),
          writes: 3,
          attempts: conflicts + 1,
        );

        _acceptedJoin(scenario, joined, roomBefore, privateBefore);
        expect(scenario.materialCalls, 1);
        expect(scenario.peer.locatorSnapshot == locatorBefore, isTrue);
        expect(scenario.peer.commits, conflicts + 1);
        expect(scenario.peer.rollbacks, conflicts);
        expect(scenario.peer.attemptedWrites, hasLength(conflicts + 1));
        expect(
          scenario.peer.attemptedWrites.every(
            (writes) => writes == scenario.peer.attemptedWrites.first,
          ),
          isTrue,
          reason:
              'unchanged reads reproduce one candidate membership and receipt',
        );
        _entryReads(scenario, scenario.joinRequest, attempts: conflicts + 1);
      },
    );
  }

  test(
    'Join replay after another Ready preserves the historical result',
    () async {
      final scenario = await _Scenario.start();
      await scenario.readyTimes(1);
      final joined = await scenario.measured(
        scenario.joinRequest,
        uid: _guestUid,
        reads: 4,
        writes: 3,
      );
      await scenario.ready(false, 'ready-after-join');
      final before = scenario.peer.documentSnapshot;
      expect(scenario.room['roomVersion'], joined.value.versionAfter + 1);

      final replay = await scenario.measured(
        scenario.joinRequest,
        uid: _guestUid,
        reads: 4,
        writes: 0,
      );

      expect(replay.value.status, api.AuthorityCommandStatus.duplicate);
      expect(replay.outcome, AuthorityOutcome.duplicate);
      expect(replay.reason, AuthorityReason.duplicateCommand);
      expect(replay.value.versionBefore, joined.value.versionBefore);
      expect(replay.value.versionAfter, joined.value.versionAfter);
      _same(replay.value.publicResult, joined.value.publicResult);
      expect(scenario.peer.documentSnapshot == before, isTrue);
      expect(scenario.peer.commits, 0);
      expect(scenario.peer.rollbacks, 1);
      _entryReads(scenario, scenario.joinRequest);
    },
  );

  for (final differentActor in [true, false]) {
    test('${differentActor ? 'actor' : 'code/hash'} collision cannot repeat Join', () async {
      final scenario = await _Scenario.start();
      await scenario.readyTimes(1);
      await scenario.measured(
        scenario.joinRequest,
        uid: _guestUid,
        reads: 4,
        writes: 3,
      );
      final before = scenario.peer.documentSnapshot;
      final changedCode =
          '${scenario.roomCode[0] == 'A' ? 'B' : 'A'}${scenario.roomCode.substring(1)}';
      final request = differentActor
          ? scenario.joinRequest
          : _request(RoomCommandType.joinRoom, _joinId, {
              'roomCode': changedCode,
            });
      expect(
        request.inputHash == scenario.joinRequest.inputHash,
        differentActor,
      );

      final collision = await scenario.measured(
        request,
        uid: differentActor ? _hostUid : _guestUid,
        reads: differentActor ? 4 : 2,
        writes: 0,
      );

      expect(collision.outcome, AuthorityOutcome.collision);
      expect(collision.reason, AuthorityReason.commandIdCollision);
      expect(collision.value.status, api.AuthorityCommandStatus.rejected);
      expect(collision.value.errorCode, 'commandIdCollision');
      expect(
        collision.value.publicResult.keys.any(
          {
            'actorPlayerId',
            'roomSnapshot',
            'readyByPlayerId',
            'roomCode',
          }.contains,
        ),
        isFalse,
      );
      expect(scenario.peer.documentSnapshot == before, isTrue);
      expect(scenario.peer.commits, 0);
      expect(scenario.peer.rollbacks, 1);
      if (differentActor) {
        _entryReads(scenario, request);
      } else {
        expect(scenario.peer.requestedDocuments, hasLength(1));
        expect(scenario.peer.requestedDocuments.single, hasLength(2));
        expect(
          scenario.peer.requestedDocuments.single.last ==
              'roomCommands/$_joinId',
          isTrue,
        );
      }
    });
  }

  test(
    'already-member rejection after Ready persists only its replayable receipt',
    () async {
      final scenario = await _Scenario.start();
      await scenario.readyTimes(1);
      final roomBefore = scenario.room;
      final privateBefore = scenario.privateRoom;
      final locatorBefore = scenario.peer.locatorSnapshot;
      final rejected = await scenario.measured(
        scenario.joinRequest,
        uid: _hostUid,
        reads: 4,
        writes: 1,
      );

      expect(rejected.value.status, api.AuthorityCommandStatus.rejected);
      expect(rejected.value.errorCode, 'alreadyMember');
      expect(rejected.value.versionBefore, 2);
      expect(rejected.value.versionAfter, 2);
      _same(scenario.room, roomBefore);
      _same(scenario.privateRoom, privateBefore);
      expect(scenario.peer.locatorSnapshot == locatorBefore, isTrue);
      final beforeReplay = scenario.peer.documentSnapshot;
      final replay = await scenario.measured(
        scenario.joinRequest,
        uid: _hostUid,
        reads: 4,
        writes: 0,
      );
      expect(replay.value.status, api.AuthorityCommandStatus.duplicate);
      expect(replay.value.isRejectedOutcome, isTrue);
      expect(replay.value.errorCode, rejected.value.errorCode);
      _same(replay.value.publicResult, rejected.value.publicResult);
      expect(scenario.peer.documentSnapshot == beforeReplay, isTrue);
    },
  );

  for (final missingPrivate in [true, false]) {
    test(
      'Join still fails closed on ${missingPrivate ? 'missing private room' : 'inconsistent membership'}',
      () async {
        final scenario = await _Scenario.start();
        await scenario.readyTimes(1);
        final path = 'roomSecrets/${scenario.roomId}';
        if (missingPrivate) {
          scenario.peer.documents.remove(path);
        } else {
          scenario.peer.documents[path]!['memberUidByPlayerId'] = {
            'mapValue': {'fields': <String, Object?>{}},
          };
        }
        final before = scenario.peer.documentSnapshot;
        scenario.peer.resetCounters();
        final capture = AuthorityExecutionMetricsCapture();

        await expectLater(
          capture.run(
            () => scenario.execute(scenario.joinRequest, uid: _guestUid),
          ),
          throwsA(
            isA<FirstPlayableFirestoreStoreViolation>().having(
              (error) => error.code,
              'safe code',
              missingPrivate
                  ? 'inconsistentRoomBoundary'
                  : 'inconsistentRoomMembership',
            ),
          ),
        );

        _metrics(capture.metrics, scenario.peer, reads: 4, writes: 0);
        expect(scenario.peer.documentSnapshot == before, isTrue);
        expect(scenario.peer.commits, 0);
        expect(scenario.peer.rollbacks, 1);
      },
    );
  }

  test(
    'Join mutation permits positive versions independent of member count',
    () {
      for (final version in [2, 3, 9]) {
        final mutation = _mutation(version: version);
        expect(mutation.roomVersion, version);
        expect(mutation.membersAfter, hasLength(2));
      }
    },
  );

  test('Join mutation still rejects zero and negative versions', () {
    for (final version in [0, -1]) {
      expect(() => _mutation(version: version), _invalidMutation);
    }
  });

  test('Create retains its existing version and timestamp guards', () {
    final members = [_members.first];
    FirstPlayableRoomEntryMutation create({
      int version = 1,
      DateTime? updatedAt,
      DateTime? expiresAt,
    }) => _mutation(
      kind: FirstPlayableRoomEntryKind.create,
      version: version,
      members: members,
      updatedAt: updatedAt,
      expiresAt: expiresAt,
    );
    final expiry = _now.add(const Duration(hours: 1));
    expect(create(updatedAt: _now, expiresAt: expiry).roomVersion, 1);
    for (final version in [0, 2]) {
      expect(
        () => create(version: version, updatedAt: _now, expiresAt: expiry),
        _invalidMutation,
      );
    }
    for (final timestamps in [
      (null, null),
      (_now, null),
      (null, expiry),
      (_now, _now),
      (_now, _now.subtract(const Duration(seconds: 1))),
    ]) {
      expect(
        () => create(updatedAt: timestamps.$1, expiresAt: timestamps.$2),
        _invalidMutation,
      );
    }
  });

  test('shared mutation identity and membership guards remain intact', () {
    final invalid = <FirstPlayableRoomEntryMutation Function()>[
      () => _mutation(codeHash: 'not-a-hash'),
      () => _mutation(roomId: ''),
      () => _mutation(hostUid: ''),
      () => _mutation(hostUid: 'synthetic-outsider'),
      () => _mutation(presetId: ''),
      () => _mutation(rulesVersion: ''),
      () => _mutation(members: []),
      () => _mutation(members: [_members.first, _members.first]),
      () => _mutation(
        members: [
          _members.first,
          ReadyRoomMember(
            uid: _guestUid,
            playerId: _members.first.playerId,
            kind: PlayerKind.human,
            ready: false,
          ),
        ],
      ),
      () => _mutation(
        updatedAt: _now,
        expiresAt: _now.add(const Duration(hours: 1)),
      ),
    ];
    for (final construct in invalid) {
      expect(construct, _invalidMutation);
    }
  });
}

void _acceptedJoin(
  _Scenario scenario,
  AuthorityExecutionResult<api.AuthorityCommandReply> result,
  Map<String, Object?> roomBefore,
  Map<String, Object?> privateBefore,
) {
  expect(result.value.status, api.AuthorityCommandStatus.accepted);
  final versionBefore = roomBefore['roomVersion']! as int;
  expect(result.value.versionBefore, versionBefore);
  expect(result.value.versionAfter, versionBefore + 1);
  final playerId = result.value.publicResult['actorPlayerId']! as String;
  final memberUids = roomBefore['memberUids']! as List;
  final ready = roomBefore['readyByUid']! as Map<String, Object?>;
  final mapping = privateBefore['memberUidByPlayerId']! as Map<String, Object?>;
  _same(scenario.room, {
    ...roomBefore,
    'roomVersion': versionBefore + 1,
    'memberUids': [...memberUids, _guestUid],
    'readyByUid': {...ready, _guestUid: false},
  });
  _same(scenario.privateRoom, {
    ...privateBefore,
    'memberUidByPlayerId': {...mapping, playerId: _guestUid},
  });
  final receipt = scenario.peer.document('roomCommands/$_joinId');
  expect(receipt['inputHash'] == scenario.joinRequest.inputHash, isTrue);
  expect(receipt['inputHashVersion'], scenario.joinRequest.inputHashVersion);
  expect(receipt['actorUid'] == _guestUid, isTrue);
  expect(scenario.peer.documentSnapshot.contains(scenario.roomCode), isFalse);
  final publicReply = CanonicalDomainJson.encode(result.value.toWireJson());
  expect(
    publicReply.contains(_hostUid) || publicReply.contains(_guestUid),
    isFalse,
  );
  expect(
    scenario.peer.documents.keys.any(
      (path) => path.startsWith('games/') || path.startsWith('gameSecrets/'),
    ),
    isFalse,
  );
}

void _same(Map<String, Object?> actual, Map<String, Object?> expected) =>
    expect(
      CanonicalDomainJson.encode(actual) ==
          CanonicalDomainJson.encode(expected),
      isTrue,
      reason: 'encoded state equality without dumping private document values',
    );

void _entryReads(
  _Scenario scenario,
  api.AuthorityCommandRequest request, {
  int attempts = 1,
}) {
  expect(scenario.peer.requestedDocuments, hasLength(2 * attempts));
  for (var attempt = 0; attempt < attempts; attempt += 1) {
    final locatorAndReceipt = scenario.peer.requestedDocuments[2 * attempt];
    expect(locatorAndReceipt, hasLength(2));
    expect(locatorAndReceipt.first.startsWith('roomCodes/'), isTrue);
    expect(
      locatorAndReceipt.last == 'roomCommands/${request.commandId}',
      isTrue,
    );
    expect(
      scenario.peer.requestedDocuments[2 * attempt + 1].join('|') ==
          'rooms/${scenario.roomId}|roomSecrets/${scenario.roomId}',
      isTrue,
    );
  }
}

final class _Scenario {
  _Scenario(this.peer) {
    final catalog = syntheticRollCatalog();
    final material = FirstPlayableAuthorityMaterialFactory(
      key: List.generate(32, (index) => index),
      roomCodeTtl: const Duration(hours: 1),
    );
    executor = FirstPlayableAuthorityExecutor(
      store: peer.store,
      rulesCatalogRepository: PinnedFirstPlayableRulesCatalogRepository(
        activeRulesVersion: catalog.rulesVersion,
        catalogs: [catalog],
      ),
      roomEntryMaterialFactory: (command, receivedAt) {
        materialCalls += 1;
        return material.roomEntry(command, receivedAt);
      },
    );
  }

  static Future<_Scenario> start() async {
    final peer = await _Peer.start();
    addTearDown(peer.close);
    final scenario = _Scenario(peer);
    final created = await scenario.measured(
      _request(RoomCommandType.createRoom, 'create-room', {
        'presetDraft': {'presetId': 'express'},
      }),
      uid: _hostUid,
      reads: 4,
      writes: 4,
    );
    expect(created.value.status, api.AuthorityCommandStatus.accepted);
    expect(created.value.versionBefore, 0);
    expect(created.value.versionAfter, 1);
    scenario.roomId = created.value.publicResult['roomId']! as String;
    scenario.roomCode = created.value.publicResult['roomCode']! as String;
    expect(scenario.room['roomVersion'], 1);
    expect(scenario.room['memberUids'], hasLength(1));
    return scenario;
  }

  final _Peer peer;
  late final FirstPlayableAuthorityExecutor executor;
  late final String roomId;
  late final String roomCode;
  int materialCalls = 0;

  Map<String, Object?> get room => peer.document('rooms/$roomId');
  Map<String, Object?> get privateRoom => peer.document('roomSecrets/$roomId');
  api.AuthorityCommandRequest get joinRequest =>
      _request(RoomCommandType.joinRoom, _joinId, {'roomCode': roomCode});

  Future<void> readyTimes(int count) async {
    for (var index = 0; index < count; index += 1) {
      await ready(index.isEven, 'ready-$index');
    }
  }

  Future<void> ready(bool value, String commandId) async {
    final previousVersion = room['roomVersion']! as int;
    final privateBefore = privateRoom;
    final result = await measured(
      _request(RoomCommandType.setReady, commandId, {
        'roomId': roomId,
        'ready': value,
      }, version: previousVersion),
      uid: _hostUid,
      reads: 3,
      writes: 2,
    );
    expect(result.value.status, api.AuthorityCommandStatus.accepted);
    expect(result.value.versionAfter, previousVersion + 1);
    expect(room['roomVersion'], previousVersion + 1);
    expect((room['readyByUid']! as Map)[_hostUid], value);
    _same(privateRoom, privateBefore);
  }

  Future<AuthorityExecutionResult<api.AuthorityCommandReply>> execute(
    api.AuthorityCommandRequest request, {
    required String uid,
  }) => executor.executeCommand(
    context: IngressContext(requestReceivedAt: _now),
    identity: VerifiedIdentity(uid: uid, authTime: _now),
    request: request,
  );

  Future<AuthorityExecutionResult<api.AuthorityCommandReply>> measured(
    api.AuthorityCommandRequest request, {
    required String uid,
    required int reads,
    required int writes,
    int attempts = 1,
  }) async {
    peer.resetCounters();
    materialCalls = 0;
    final capture = AuthorityExecutionMetricsCapture();
    final result = await capture.run(() => execute(request, uid: uid));
    for (final metrics in [result.metrics, capture.metrics]) {
      _metrics(metrics, peer, reads: reads, writes: writes, attempts: attempts);
    }
    expect(result.metrics.schemaVersion, 1);
    expect(result.metrics.stateVersion, result.value.versionAfter);
    expect(capture.metrics.schemaVersion, isNull);
    expect(capture.metrics.stateVersion, isNull);
    return result;
  }
}

api.AuthorityCommandRequest _request(
  RoomCommandType type,
  String commandId,
  Map<String, Object?> payload, {
  int? version,
}) => api.AuthorityCommandRequest.room(
  RoomCommand(
    commandId: commandId,
    schemaVersion: 1,
    expectedRoomVersion: version,
    clientInstanceId: 'synthetic-join-ready-client',
    type: type,
    payload: payload,
  ),
);

void _metrics(
  AuthorityExecutionMetrics metrics,
  _Peer peer, {
  required int reads,
  required int writes,
  int attempts = 1,
}) {
  expect(metrics.retryCount, attempts - 1);
  expect(metrics.conflictCount, attempts - 1);
  expect(metrics.firestoreReadCount, reads);
  expect(
    metrics.firestoreReadCount,
    peer.requestedDocuments.expand((batch) => batch).length,
  );
  expect(metrics.firestoreWriteCount, writes);
  expect(peer.confirmedWrites, writes);
  expect(metrics.bytesRead, peer.responseBytes);
  expect(metrics.bytesWritten, peer.requestBytes);
  expect(metrics.bytesRead, greaterThan(0));
  expect(metrics.bytesWritten, greaterThan(0));
  expect(metrics.snapshotBytes, 0);
  expect(metrics.coldStart, isFalse);
  expect(peer.begins, attempts);
}

FirstPlayableRoomEntryMutation _mutation({
  FirstPlayableRoomEntryKind kind = FirstPlayableRoomEntryKind.join,
  int version = 2,
  List<ReadyRoomMember> members = _members,
  String? codeHash,
  String roomId = 'synthetic-constructor-room',
  String hostUid = _hostUid,
  String presetId = 'express',
  String rulesVersion = 'synthetic-rules-vp0',
  DateTime? updatedAt,
  DateTime? expiresAt,
}) => FirstPlayableRoomEntryMutation(
  kind: kind,
  codeHash: codeHash ?? 'a' * 64,
  roomId: roomId,
  roomVersion: version,
  hostUid: hostUid,
  presetId: presetId,
  rulesVersion: rulesVersion,
  membersAfter: members,
  updatedAt: updatedAt,
  expiresAt: expiresAt,
);

final _invalidMutation = throwsA(
  isA<FirstPlayableAuthorityExecutorViolation>().having(
    (error) => error.code,
    'safe code',
    'invalidRoomEntryMutation',
  ),
);

final class _Peer {
  _Peer(this.server) {
    store = FirstPlayableFirestoreRestStore(
      config: FirstPlayableFirestoreRestConfig.emulator(
        projectId: 'demo-join-after-ready',
        host: '127.0.0.1:${server.port}',
        maxAttempts: 3,
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
  final attemptedWrites = <String>[];
  int conflicts = 0;
  int begins = 0;
  int commits = 0;
  int rollbacks = 0;
  int confirmedWrites = 0;
  int requestBytes = 0;
  int responseBytes = 0;

  String get documentSnapshot => CanonicalDomainJson.encode(documents);
  String get locatorSnapshot => CanonicalDomainJson.encode({
    for (final entry in documents.entries)
      if (entry.key.startsWith('roomCodes/')) entry.key: entry.value,
  });
  Map<String, Object?> document(String path) => {
    for (final entry in documents[path]!.entries)
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
    attemptedWrites.clear();
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
        response = {'transaction': 'synthetic-join-ready-${++begins}'};
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
        attemptedWrites.add(CanonicalDomainJson.encode({'writes': writes}));
        if (conflicts > 0) {
          conflicts -= 1;
          status = HttpStatus.conflict;
          response = {
            'error': {'status': 'ABORTED', 'message': 'synthetic ñ'},
          };
        } else {
          for (final write in writes) {
            final update = write['update']! as Map<String, Object?>;
            final path = (update['name']! as String).split('/documents/').last;
            final fields = update['fields']! as Map<String, Object?>;
            // Only the store's current top-level update masks are supported.
            if (write['updateMask'] case final Map<String, Object?> mask) {
              final paths = (mask['fieldPaths']! as List).cast<String>();
              if (paths.length != fields.length ||
                  paths.any((path) => !fields.containsKey(path))) {
                throw StateError('unsupportedSyntheticFieldMask');
              }
              documents[path] = {...?documents[path], ...fields};
            } else {
              documents[path] = {...fields};
            }
          }
          confirmedWrites += writes.length;
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
  throw StateError('unsupportedSyntheticRoomField');
}

final _now = DateTime.utc(2026, 9, 9, 1);
const _joinId = 'join-guest';
const _hostUid = 'synthetic-host-ñ';
const _guestUid = 'synthetic-guest-🌿';
const _members = [
  ReadyRoomMember(
    uid: _hostUid,
    playerId: 'p1',
    kind: PlayerKind.human,
    ready: true,
  ),
  ReadyRoomMember(
    uid: _guestUid,
    playerId: 'p2',
    kind: PlayerKind.human,
    ready: false,
  ),
];
