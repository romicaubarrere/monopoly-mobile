import 'dart:io';

import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_command_service/command_service.dart';
import 'package:board_command_service/observability/authority_observability.dart';
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

void main() {
  final emulatorHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  final skipReason = emulatorHost == null
      ? 'requires FIRESTORE_EMULATOR_HOST'
      : false;

  test('Emulator admin credential is restricted to numeric loopback', () {
    for (final host in <String>[
      'localhost:8080',
      'firestore.example.com:8080',
      'http://127.0.0.1:8080',
    ]) {
      expect(
        () => FirstPlayableFirestoreRestConfig.emulator(
          projectId: 'demo-board-game-local',
          host: host,
        ),
        throwsA(
          isA<FirstPlayableFirestoreStoreViolation>().having(
            (error) => error.code,
            'code',
            'emulatorHostMustBeNumericLoopback',
          ),
        ),
      );
    }
  });

  test(
    'Dart store persists room/start/game and lost-ACK on Firestore Emulator',
    () async {
      final store = FirstPlayableFirestoreRestStore(
        config: FirstPlayableFirestoreRestConfig.emulator(
          projectId:
              Platform.environment['GCLOUD_PROJECT'] ?? 'demo-board-game-local',
          host: emulatorHost!,
        ),
      );
      const roomId = 'room-rest-vp0';
      const codeHash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      const host = ReadyRoomMember(
        uid: 'uid-p1',
        playerId: 'p1',
        kind: PlayerKind.human,
        ready: false,
      );
      const guest = ReadyRoomMember(
        uid: 'uid-p2',
        playerId: 'p2',
        kind: PlayerKind.human,
        ready: false,
      );

      final create = await store.transactRoomEntry(
        kind: FirstPlayableRoomEntryKind.create,
        codeHash: codeHash,
        roomId: roomId,
        commandId: 'cmd-create-rest',
        evaluate: (view) {
          expect(view.locator, isNull);
          expect(view.room, isNull);
          expect(view.storedReceipt, isNull);
          return FirstPlayableRoomEntryTransactionDecision(
            reply: _reply(commandId: 'cmd-create-rest', before: 0, after: 1),
            outcome: AuthorityOutcome.success,
            reason: AuthorityReason.none,
            mutation: FirstPlayableRoomEntryMutation(
              kind: FirstPlayableRoomEntryKind.create,
              codeHash: codeHash,
              roomId: roomId,
              roomVersion: 1,
              hostUid: host.uid,
              presetId: 'express',
              rulesVersion: syntheticRollCatalog().rulesVersion,
              membersAfter: const <ReadyRoomMember>[host],
              updatedAt: DateTime.utc(2026, 8, 27),
              expiresAt: DateTime.utc(2026, 8, 27, 1),
            ),
            receiptToPersist: _receipt(
              commandId: 'cmd-create-rest',
              actorUid: host.uid,
              before: 0,
              after: 1,
              hashCharacter: '1',
              roomEntryCodeHash: codeHash,
            ),
          );
        },
      );
      expect(create.metrics.firestoreWriteCount, 4);

      final duplicate = await store.transactRoomEntry(
        kind: FirstPlayableRoomEntryKind.create,
        codeHash: codeHash,
        roomId: roomId,
        commandId: 'cmd-create-rest',
        evaluate: (view) {
          expect(view.storedReceipt?.actorUid, host.uid);
          return FirstPlayableRoomEntryTransactionDecision(
            reply: api.AuthorityCommandReply(
              commandId: 'cmd-create-rest',
              status: api.AuthorityCommandStatus.duplicate,
              versionBefore: 0,
              versionAfter: 1,
              publicResult: view.storedReceipt!.receipt.publicResult,
            ),
            outcome: AuthorityOutcome.duplicate,
            reason: AuthorityReason.duplicateCommand,
          );
        },
      );
      expect(duplicate.metrics.firestoreWriteCount, 0);

      final join = await store.transactRoomEntry(
        kind: FirstPlayableRoomEntryKind.join,
        codeHash: codeHash,
        commandId: 'cmd-join-rest',
        evaluate: (view) {
          expect(view.locator?.roomId, roomId);
          expect(view.room?.members, hasLength(1));
          return FirstPlayableRoomEntryTransactionDecision(
            reply: _reply(commandId: 'cmd-join-rest', before: 1, after: 2),
            outcome: AuthorityOutcome.success,
            reason: AuthorityReason.none,
            mutation: FirstPlayableRoomEntryMutation(
              kind: FirstPlayableRoomEntryKind.join,
              codeHash: codeHash,
              roomId: roomId,
              roomVersion: 2,
              hostUid: host.uid,
              presetId: 'express',
              rulesVersion: syntheticRollCatalog().rulesVersion,
              membersAfter: const <ReadyRoomMember>[host, guest],
            ),
            receiptToPersist: _receipt(
              commandId: 'cmd-join-rest',
              actorUid: guest.uid,
              before: 1,
              after: 2,
              hashCharacter: '2',
              roomEntryCodeHash: codeHash,
            ),
          );
        },
      );
      expect(join.metrics.firestoreWriteCount, 3);

      const readyMembers = <ReadyRoomMember>[
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
      await store.transactRoom(
        roomId: roomId,
        commandId: 'cmd-ready-rest',
        evaluate: (view) {
          expect(view.members, hasLength(2));
          return FirstPlayableRoomTransactionDecision(
            reply: _reply(commandId: 'cmd-ready-rest', before: 2, after: 3),
            outcome: AuthorityOutcome.success,
            reason: AuthorityReason.none,
            membersAfter: readyMembers,
            receiptToPersist: _receipt(
              commandId: 'cmd-ready-rest',
              actorUid: host.uid,
              before: 2,
              after: 3,
              hashCharacter: '3',
            ),
          );
        },
      );

      final roomRead = await store.readRoom(roomId: roomId);
      expect(roomRead.view.roomVersion, 3);
      expect(roomRead.view.members.every((member) => member.ready), isTrue);
      expect(roomRead.metrics.firestoreWriteCount, 0);

      final startPlan = ReadyStartPlanner.plan(
        command: RoomCommand(
          commandId: 'cmd-start-rest',
          schemaVersion: 1,
          expectedRoomVersion: 3,
          clientInstanceId: 'server-test',
          type: RoomCommandType.startGame,
          payload: const <String, Object?>{'roomId': roomId},
        ),
        authenticatedActorUid: host.uid,
        hostUid: host.uid,
        gameId: 'game-vp0',
        presetId: 'express',
        members: readyMembers,
        catalog: syntheticRollCatalog(),
        secureSeed: syntheticRollSeed,
      );
      final started = await store.transactRoom(
        roomId: roomId,
        commandId: 'cmd-start-rest',
        evaluate: (view) {
          expect(view.members.every((member) => member.ready), isTrue);
          return FirstPlayableRoomTransactionDecision(
            reply: _reply(commandId: 'cmd-start-rest', before: 3, after: 4),
            outcome: AuthorityOutcome.success,
            reason: AuthorityReason.none,
            startPlan: startPlan,
            startMemberUidByPlayerId: const <String, String>{
              'p1': 'uid-p1',
              'p2': 'uid-p2',
            },
            receiptToPersist: _receipt(
              commandId: 'cmd-start-rest',
              actorUid: host.uid,
              before: 3,
              after: 4,
              hashCharacter: '4',
            ),
          );
        },
      );
      expect(started.metrics.firestoreWriteCount, 4);

      final read = await store.readGame(gameId: 'game-vp0');
      expect(read.view.publicState.header.stateVersion, 0);
      expect(read.view.memberUidByPlayerId, const <String, String>{
        'p1': 'uid-p1',
        'p2': 'uid-p2',
      });
      expect(read.view.privateRng?.seed, orderedEquals(syntheticRollSeed));

      final gameplay = await store.transactGame(
        gameId: 'game-vp0',
        commandId: 'cmd-game-rest',
        evaluate: (view) {
          expect(view.publicState.header.stateVersion, 0);
          return FirstPlayableGameTransactionDecision(
            reply: _reply(commandId: 'cmd-game-rest', before: 0, after: 1),
            outcome: AuthorityOutcome.success,
            reason: AuthorityReason.none,
            publicStateAfter: syntheticRollState(stateVersion: 1),
            privateRngAfter: syntheticRollPrivateState(),
            receiptToPersist: _receipt(
              commandId: 'cmd-game-rest',
              actorUid: host.uid,
              before: 0,
              after: 1,
              hashCharacter: '5',
            ),
          );
        },
      );
      expect(gameplay.metrics.firestoreWriteCount, 3);

      final recovered = await store.readGame(
        gameId: 'game-vp0',
        commandId: 'cmd-game-rest',
      );
      expect(recovered.view.publicState.header.stateVersion, 1);
      expect(recovered.view.storedReceipt?.actorUid, host.uid);
      expect(recovered.view.storedReceipt?.receipt.commandId, 'cmd-game-rest');
    },
    skip: skipReason,
  );
}

api.AuthorityCommandReply _reply({
  required String commandId,
  required int before,
  required int after,
}) => api.AuthorityCommandReply(
  commandId: commandId,
  status: api.AuthorityCommandStatus.accepted,
  versionBefore: before,
  versionAfter: after,
  publicResult: <String, Object?>{
    'status': 'accepted',
    'stateVersionBefore': before,
    'stateVersionAfter': after,
  },
);

StoredAuthorityCommandReceipt _receipt({
  required String commandId,
  required String actorUid,
  required int before,
  required int after,
  required String hashCharacter,
  String? roomEntryCodeHash,
}) => StoredAuthorityCommandReceipt(
  actorUid: actorUid,
  roomEntryCodeHash: roomEntryCodeHash,
  receipt: DurableCommandReceipt(
    commandId: commandId,
    inputHashVersion: 1,
    inputHash: List<String>.filled(64, hashCharacter).join(),
    publicResult: <String, Object?>{
      'status': 'accepted',
      'stateVersionBefore': before,
      'stateVersionAfter': after,
    },
  ),
);
