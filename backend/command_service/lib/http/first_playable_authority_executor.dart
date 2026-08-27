import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_game_contracts/game_contracts.dart';
import 'package:board_game_core/game_core.dart';

import '../buy_auction_planner.dart';
import '../ingress/command_ingress.dart';
import '../observability/authority_observability.dart';
import '../reconnect_planner.dart' as reconnect_planner;
import '../ready_start_planner.dart';
import '../rng_operation_planner.dart';
import '../roll_movement_planner.dart';
import '../security/firebase_identity_verifier.dart';
import '../security/membership_authorizer.dart';
import 'authority_http_ingress.dart';
import 'first_playable_response_adapter.dart';
import 'first_playable_rules_catalog_repository.dart';

final class FirstPlayableAuthorityExecutorViolation implements Exception {
  const FirstPlayableAuthorityExecutorViolation(this.code);

  final String code;

  @override
  String toString() => 'FirstPlayableAuthorityExecutorViolation: $code';
}

/// Private receipt record loaded from the command document in the same
/// transaction as the authoritative game state.
///
/// [actorUid] never crosses the public response boundary. It prevents another
/// room member from replaying an otherwise matching command identity.
final class StoredAuthorityCommandReceipt {
  const StoredAuthorityCommandReceipt({
    required this.actorUid,
    required this.receipt,
    this.roomEntryCodeHash,
  });

  final String actorUid;
  final reconnect_planner.DurableCommandReceipt receipt;

  /// Internal hash-only binding used to prove that a retried Create/Join
  /// material factory reproduced the same room-code candidate. The raw room
  /// code is never persisted in the receipt.
  final String? roomEntryCodeHash;
}

/// Typed Firestore transaction view required by the VP0 command executor.
///
/// A concrete adapter decodes Firestore documents once, then supplies the
/// canonical domain objects here. The executor never accepts client-owned game
/// state and never interprets gameplay fields itself.
final class FirstPlayableGameTransactionView {
  FirstPlayableGameTransactionView({
    required this.publicState,
    required Map<String, String> memberUidByPlayerId,
    required this.privateRng,
    this.storedReceipt,
  }) : memberUidByPlayerId = Map.unmodifiable(memberUidByPlayerId) {
    if (this.memberUidByPlayerId.entries.any(
      (entry) => entry.key.isEmpty || entry.value.isEmpty,
    )) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidMemberMapping',
      );
    }
    if (this.memberUidByPlayerId.values.toSet().length !=
        this.memberUidByPlayerId.length) {
      throw const FirstPlayableAuthorityExecutorViolation('duplicateMemberUid');
    }
  }

  final PublicGameState publicState;
  final Map<String, String> memberUidByPlayerId;
  final AuthorityPrivateRngSnapshot? privateRng;
  final StoredAuthorityCommandReceipt? storedReceipt;
}

/// One deterministic transaction decision returned to the Firestore adapter.
///
/// When [publicStateAfter] is present, the adapter commits it atomically with
/// [receiptToPersist] and, for Roll, [privateRngAfter]. Rejections persist only
/// their safe receipt. Duplicate/collision decisions perform zero writes.
final class FirstPlayableGameTransactionDecision {
  FirstPlayableGameTransactionDecision({
    required this.reply,
    required this.outcome,
    required this.reason,
    this.publicStateAfter,
    this.privateRngAfter,
    this.receiptToPersist,
  }) {
    final accepted = reply.status == api.AuthorityCommandStatus.accepted;
    final replay = reply.status == api.AuthorityCommandStatus.duplicate;
    if (accepted != (publicStateAfter != null) ||
        accepted && receiptToPersist == null ||
        replay &&
            (publicStateAfter != null ||
                privateRngAfter != null ||
                receiptToPersist != null) ||
        !accepted && privateRngAfter != null) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidTransactionDecision',
      );
    }
  }

  final api.AuthorityCommandReply reply;
  final AuthorityOutcome outcome;
  final AuthorityReason reason;
  final PublicGameState? publicStateAfter;
  final AuthorityPrivateRngSnapshot? privateRngAfter;
  final StoredAuthorityCommandReceipt? receiptToPersist;
}

final class FirstPlayableGameTransactionResult {
  const FirstPlayableGameTransactionResult({
    required this.decision,
    this.metrics = const AuthorityExecutionMetrics(),
  });

  final FirstPlayableGameTransactionDecision decision;
  final AuthorityExecutionMetrics metrics;
}

final class FirstPlayableGameReadResult {
  const FirstPlayableGameReadResult({
    required this.view,
    this.metrics = const AuthorityExecutionMetrics(),
  });

  final FirstPlayableGameTransactionView view;
  final AuthorityExecutionMetrics metrics;
}

final class FirstPlayableRoomReadResult {
  const FirstPlayableRoomReadResult({
    required this.view,
    this.metrics = const AuthorityExecutionMetrics(),
  });

  final FirstPlayableRoomTransactionView view;
  final AuthorityExecutionMetrics metrics;
}

/// Authority-private material generated once before Firestore retries StartGame.
final class FirstPlayableStartMaterial {
  FirstPlayableStartMaterial({required this.gameId, required List<int> seed})
    : seed = List<int>.unmodifiable(seed) {
    if (gameId.isEmpty || this.seed.length != 32) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidStartMaterial',
      );
    }
  }

  final String gameId;
  final List<int> seed;
}

typedef FirstPlayableStartMaterialFactory =
    Future<FirstPlayableStartMaterial> Function(RoomCommand command);

enum FirstPlayableRoomEntryKind { create, join }

/// Authority-owned material generated before Firestore retries Create/Join.
///
/// Implementations must return the same material for the same commandId. This
/// lets a lost-ACK retry reproduce the public room code without persisting that
/// plaintext code in Firestore.
final class FirstPlayableRoomEntryMaterial {
  FirstPlayableRoomEntryMaterial({
    required this.kind,
    required this.roomCode,
    required this.codeHash,
    required this.playerId,
    this.roomId,
    this.expiresAt,
  }) {
    final create = kind == FirstPlayableRoomEntryKind.create;
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(roomCode) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(codeHash) ||
        playerId.isEmpty ||
        create != (roomId != null && expiresAt != null) ||
        roomId != null && roomId!.isEmpty) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidRoomEntryMaterial',
      );
    }
  }

  final FirstPlayableRoomEntryKind kind;
  final String roomCode;
  final String codeHash;
  final String playerId;
  final String? roomId;
  final DateTime? expiresAt;
}

typedef FirstPlayableRoomEntryMaterialFactory =
    Future<FirstPlayableRoomEntryMaterial> Function(
      RoomCommand command,
      DateTime requestReceivedAt,
    );

final class FirstPlayableRoomLocatorView {
  FirstPlayableRoomLocatorView({
    required this.roomId,
    required DateTime expiresAt,
  }) : expiresAt = expiresAt.toUtc() {
    if (roomId.isEmpty) {
      throw const FirstPlayableAuthorityExecutorViolation('invalidRoomLocator');
    }
  }

  final String roomId;
  final DateTime expiresAt;
}

/// Public/private room documents decoded together by the store adapter.
final class FirstPlayableRoomEntryRoomView {
  FirstPlayableRoomEntryRoomView({
    required this.roomId,
    required this.roomVersion,
    required this.status,
    required this.hostUid,
    required this.presetId,
    required this.rulesVersion,
    required List<ReadyRoomMember> members,
  }) : members = List<ReadyRoomMember>.unmodifiable(members) {
    final memberUids = this.members.map((member) => member.uid).toList();
    final playerIds = this.members.map((member) => member.playerId).toList();
    if (roomId.isEmpty ||
        roomVersion < 1 ||
        status.isEmpty ||
        hostUid.isEmpty ||
        presetId.isEmpty ||
        rulesVersion.isEmpty ||
        this.members.isEmpty ||
        this.members.any(
          (member) => member.uid.isEmpty || member.playerId.isEmpty,
        ) ||
        memberUids.toSet().length != memberUids.length ||
        playerIds.toSet().length != playerIds.length ||
        !memberUids.contains(hostUid)) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidRoomEntryView',
      );
    }
  }

  final String roomId;
  final int roomVersion;
  final String status;
  final String hostUid;
  final String presetId;
  final String rulesVersion;
  final List<ReadyRoomMember> members;
}

final class FirstPlayableRoomEntryTransactionView {
  const FirstPlayableRoomEntryTransactionView({
    this.locator,
    this.room,
    this.storedReceipt,
  });

  final FirstPlayableRoomLocatorView? locator;
  final FirstPlayableRoomEntryRoomView? room;
  final StoredAuthorityCommandReceipt? storedReceipt;
}

/// Hash-only mutation projected by the persistence codec into public and
/// private Firestore documents. [membersAfter] is split by the codec; it never
/// crosses the HTTP response boundary.
final class FirstPlayableRoomEntryMutation {
  FirstPlayableRoomEntryMutation({
    required this.kind,
    required this.codeHash,
    required this.roomId,
    required this.roomVersion,
    required this.hostUid,
    required this.presetId,
    required this.rulesVersion,
    required List<ReadyRoomMember> membersAfter,
    this.updatedAt,
    this.expiresAt,
  }) : membersAfter = List<ReadyRoomMember>.unmodifiable(membersAfter) {
    final create = kind == FirstPlayableRoomEntryKind.create;
    final memberUids = this.membersAfter.map((member) => member.uid).toList();
    final playerIds = this.membersAfter
        .map((member) => member.playerId)
        .toList();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(codeHash) ||
        roomId.isEmpty ||
        roomVersion != this.membersAfter.length ||
        hostUid.isEmpty ||
        presetId.isEmpty ||
        rulesVersion.isEmpty ||
        this.membersAfter.isEmpty ||
        memberUids.toSet().length != memberUids.length ||
        playerIds.toSet().length != playerIds.length ||
        !memberUids.contains(hostUid) ||
        create != (updatedAt != null && expiresAt != null) ||
        create && !expiresAt!.isAfter(updatedAt!)) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidRoomEntryMutation',
      );
    }
  }

  final FirstPlayableRoomEntryKind kind;
  final String codeHash;
  final String roomId;
  final int roomVersion;
  final String hostUid;
  final String presetId;
  final String rulesVersion;
  final List<ReadyRoomMember> membersAfter;
  final DateTime? updatedAt;
  final DateTime? expiresAt;
}

final class FirstPlayableRoomEntryTransactionDecision {
  FirstPlayableRoomEntryTransactionDecision({
    required this.reply,
    required this.outcome,
    required this.reason,
    this.mutation,
    this.receiptToPersist,
  }) {
    final accepted = reply.status == api.AuthorityCommandStatus.accepted;
    final duplicate = reply.status == api.AuthorityCommandStatus.duplicate;
    final collision = outcome == AuthorityOutcome.collision;
    if (accepted != (mutation != null) ||
        accepted && receiptToPersist == null ||
        duplicate && (mutation != null || receiptToPersist != null) ||
        collision && (mutation != null || receiptToPersist != null) ||
        !accepted && !duplicate && !collision && receiptToPersist == null) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidRoomEntryDecision',
      );
    }
  }

  final api.AuthorityCommandReply reply;
  final AuthorityOutcome outcome;
  final AuthorityReason reason;
  final FirstPlayableRoomEntryMutation? mutation;
  final StoredAuthorityCommandReceipt? receiptToPersist;
}

final class FirstPlayableRoomEntryTransactionResult {
  const FirstPlayableRoomEntryTransactionResult({
    required this.decision,
    this.metrics = const AuthorityExecutionMetrics(),
  });

  final FirstPlayableRoomEntryTransactionDecision decision;
  final AuthorityExecutionMetrics metrics;
}

typedef FirstPlayableRoomEntryTransactionCallback =
    FirstPlayableRoomEntryTransactionDecision Function(
      FirstPlayableRoomEntryTransactionView view,
    );

/// Consistent room view loaded by the durable adapter transaction.
final class FirstPlayableRoomTransactionView {
  FirstPlayableRoomTransactionView({
    required this.roomId,
    required this.roomVersion,
    required this.status,
    required this.hostUid,
    required this.presetId,
    required this.rulesVersion,
    required List<ReadyRoomMember> members,
    this.storedReceipt,
  }) : members = List<ReadyRoomMember>.unmodifiable(members) {
    final memberUids = members.map((member) => member.uid).toList();
    final playerIds = members.map((member) => member.playerId).toList();
    if (roomId.isEmpty ||
        roomVersion < 0 ||
        status.isEmpty ||
        hostUid.isEmpty ||
        presetId.isEmpty ||
        rulesVersion.isEmpty ||
        members.isEmpty ||
        members.any(
          (member) => member.uid.isEmpty || member.playerId.isEmpty,
        ) ||
        memberUids.toSet().length != memberUids.length ||
        playerIds.toSet().length != playerIds.length) {
      throw const FirstPlayableAuthorityExecutorViolation('invalidRoomView');
    }
  }

  final String roomId;
  final int roomVersion;
  final String status;
  final String hostUid;
  final String presetId;
  final String rulesVersion;
  final List<ReadyRoomMember> members;
  final StoredAuthorityCommandReceipt? storedReceipt;
}

/// Atomic room mutation selected by the Ready/Start executor.
///
/// SetReady updates [membersAfter]. StartGame persists [startPlan] as the room,
/// public game and private game documents in the same transaction. Rejections
/// persist only their safe receipt; duplicates and collisions write nothing.
final class FirstPlayableRoomTransactionDecision {
  FirstPlayableRoomTransactionDecision({
    required this.reply,
    required this.outcome,
    required this.reason,
    this.membersAfter,
    this.startPlan,
    Map<String, String>? startMemberUidByPlayerId,
    this.receiptToPersist,
  }) : startMemberUidByPlayerId = startMemberUidByPlayerId == null
           ? null
           : Map.unmodifiable(startMemberUidByPlayerId) {
    final accepted = reply.status == api.AuthorityCommandStatus.accepted;
    final replay = reply.status == api.AuthorityCommandStatus.duplicate;
    final mutationCount =
        (membersAfter == null ? 0 : 1) + (startPlan == null ? 0 : 1);
    final startPlayerIds = startPlan?.publicState.players
        .map((player) => player.playerId)
        .toSet();
    if (accepted != (mutationCount == 1) ||
        accepted && receiptToPersist == null ||
        replay && receiptToPersist != null ||
        replay && mutationCount != 0 ||
        !accepted && mutationCount != 0 ||
        (startPlan == null) != (this.startMemberUidByPlayerId == null) ||
        this.startMemberUidByPlayerId != null &&
            (this.startMemberUidByPlayerId!.entries.any(
                  (entry) => entry.key.isEmpty || entry.value.isEmpty,
                ) ||
                this.startMemberUidByPlayerId!.keys
                    .toSet()
                    .difference(startPlayerIds!)
                    .isNotEmpty ||
                startPlayerIds
                    .difference(this.startMemberUidByPlayerId!.keys.toSet())
                    .isNotEmpty ||
                this.startMemberUidByPlayerId!.values.toSet().length !=
                    this.startMemberUidByPlayerId!.length)) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'invalidRoomTransactionDecision',
      );
    }
  }

  final api.AuthorityCommandReply reply;
  final AuthorityOutcome outcome;
  final AuthorityReason reason;
  final List<ReadyRoomMember>? membersAfter;
  final ReadyStartPlan? startPlan;

  /// Authority-private membership mapping required to materialize gameSecrets
  /// during StartGame. It deliberately travels with the atomic decision and is
  /// never included in the public reply or public game document.
  final Map<String, String>? startMemberUidByPlayerId;
  final StoredAuthorityCommandReceipt? receiptToPersist;
}

final class FirstPlayableRoomTransactionResult {
  const FirstPlayableRoomTransactionResult({
    required this.decision,
    this.metrics = const AuthorityExecutionMetrics(),
  });

  final FirstPlayableRoomTransactionDecision decision;
  final AuthorityExecutionMetrics metrics;
}

typedef FirstPlayableRoomTransactionCallback =
    FirstPlayableRoomTransactionDecision Function(
      FirstPlayableRoomTransactionView view,
    );

typedef FirstPlayableGameTransactionCallback =
    FirstPlayableGameTransactionDecision Function(
      FirstPlayableGameTransactionView view,
    );

/// Minimal durable repository contract for the live Flutter vertical slice.
///
/// `transactGame` must load the game, optional private RNG document and command
/// receipt in one Firestore transaction; invoke [evaluate] inside its retry
/// callback; and atomically apply exactly the returned decision. Secure seed,
/// tokens and direct UID mappings must remain server-side.
abstract interface class FirstPlayableAuthorityStore {
  /// Atomically resolves a hash-only room locator, public/private room state
  /// and durable command receipt for CreateRoom/JoinRoom.
  Future<FirstPlayableRoomEntryTransactionResult> transactRoomEntry({
    required FirstPlayableRoomEntryKind kind,
    required String codeHash,
    String? roomId,
    required String commandId,
    required FirstPlayableRoomEntryTransactionCallback evaluate,
  });

  /// Atomically loads and mutates one room plus its command receipt. StartGame
  /// also commits the returned public/private game state in this transaction.
  Future<FirstPlayableRoomTransactionResult> transactRoom({
    required String roomId,
    required String commandId,
    required FirstPlayableRoomTransactionCallback evaluate,
  });

  Future<FirstPlayableGameTransactionResult> transactGame({
    required String gameId,
    required String commandId,
    required FirstPlayableGameTransactionCallback evaluate,
  });

  /// Consistent authority read for reconnect/public snapshot replacement.
  Future<FirstPlayableGameReadResult> readGame({
    required String gameId,
    String? commandId,
  });
}

/// Optional read port required by Flutter lobby synchronization.
///
/// It is separate from the mutation port so existing planner/unit fakes need
/// not pretend to provide a durable public-room read.
abstract interface class FirstPlayableRoomSnapshotStore {
  Future<FirstPlayableRoomReadResult> readRoom({required String roomId});
}

/// Concrete VP0 composition behind [AuthorityHttpIngress].
///
/// Rules remain in Engine planners. This class owns only authentication scope,
/// duplicate/collision classification, the atomic repository decision and the
/// public response mapping consumed by Flutter.
final class FirstPlayableAuthorityExecutor implements AuthorityHttpExecutor {
  const FirstPlayableAuthorityExecutor({
    required FirstPlayableAuthorityStore store,
    required FirstPlayableRulesCatalogRepository rulesCatalogRepository,
    FirstPlayableStartMaterialFactory? startMaterialFactory,
    FirstPlayableRoomEntryMaterialFactory? roomEntryMaterialFactory,
  }) : // Public named parameters cannot initialize private fields directly.
       // ignore: prefer_initializing_formals
       _store = store,
       // ignore: prefer_initializing_formals
       _rulesCatalogRepository = rulesCatalogRepository,
       // ignore: prefer_initializing_formals
       _startMaterialFactory = startMaterialFactory,
       // ignore: prefer_initializing_formals
       _roomEntryMaterialFactory = roomEntryMaterialFactory;

  final FirstPlayableAuthorityStore _store;
  final FirstPlayableRulesCatalogRepository _rulesCatalogRepository;
  final FirstPlayableStartMaterialFactory? _startMaterialFactory;
  final FirstPlayableRoomEntryMaterialFactory? _roomEntryMaterialFactory;

  @override
  Future<AuthorityExecutionResult<api.AuthorityCommandReply>> executeCommand({
    required IngressContext context,
    required VerifiedIdentity identity,
    required api.AuthorityCommandRequest request,
  }) async {
    if (request.family == api.AuthorityCommandFamily.room) {
      return _executeRoomCommand(
        context: context,
        identity: identity,
        request: request,
      );
    }
    final command = request.asGameCommand;
    final transaction = await _store.transactGame(
      gameId: command.gameId,
      commandId: command.commandId,
      evaluate: (view) {
        final catalog = _rulesCatalogRepository.catalogForGame(
          view.publicState,
        );
        return _evaluateGameCommand(
          context: context,
          actorUid: identity.uid,
          request: request,
          command: command,
          view: view,
          catalog: catalog,
        );
      },
    );
    final decision = transaction.decision;
    return AuthorityExecutionResult<api.AuthorityCommandReply>(
      value: decision.reply,
      outcome: decision.outcome,
      reason: decision.reason,
      metrics: transaction.metrics,
    );
  }

  Future<AuthorityExecutionResult<api.AuthorityCommandReply>>
  _executeRoomCommand({
    required IngressContext context,
    required VerifiedIdentity identity,
    required api.AuthorityCommandRequest request,
  }) async {
    final command = request.asRoomCommand;
    if (command.type == RoomCommandType.createRoom ||
        command.type == RoomCommandType.joinRoom) {
      return _executeRoomEntryCommand(
        context: context,
        identity: identity,
        request: request,
        command: command,
      );
    }
    if (command.type != RoomCommandType.setReady &&
        command.type != RoomCommandType.startGame) {
      throw FirstPlayableAuthorityExecutorViolation(
        'unsupportedRoomCommand:${command.type.wireValue}',
      );
    }
    final roomId = command.payload['roomId']! as String;
    final startMaterial = command.type == RoomCommandType.startGame
        ? await _requireStartMaterialFactory()(command)
        : null;
    final transaction = await _store.transactRoom(
      roomId: roomId,
      commandId: command.commandId,
      evaluate: (view) {
        final catalog = _rulesCatalogRepository.catalogForRoom(
          rulesVersion: view.rulesVersion,
          presetId: view.presetId,
        );
        return _evaluateRoomCommand(
          context: context,
          actorUid: identity.uid,
          request: request,
          command: command,
          view: view,
          catalog: catalog,
          startMaterial: startMaterial,
        );
      },
    );
    final decision = transaction.decision;
    return AuthorityExecutionResult<api.AuthorityCommandReply>(
      value: decision.reply,
      outcome: decision.outcome,
      reason: decision.reason,
      metrics: transaction.metrics,
    );
  }

  Future<AuthorityExecutionResult<api.AuthorityCommandReply>>
  _executeRoomEntryCommand({
    required IngressContext context,
    required VerifiedIdentity identity,
    required api.AuthorityCommandRequest request,
    required RoomCommand command,
  }) async {
    final materialFactory = _roomEntryMaterialFactory;
    if (materialFactory == null) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'roomEntryMaterialUnavailable',
      );
    }
    final material = await materialFactory(command, context.requestReceivedAt);
    final expectedKind = command.type == RoomCommandType.createRoom
        ? FirstPlayableRoomEntryKind.create
        : FirstPlayableRoomEntryKind.join;
    if (material.kind != expectedKind ||
        expectedKind == FirstPlayableRoomEntryKind.join &&
            material.roomCode != command.payload['roomCode']) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'roomEntryMaterialMismatch',
      );
    }
    final transaction = await _store.transactRoomEntry(
      kind: expectedKind,
      codeHash: material.codeHash,
      roomId: material.roomId,
      commandId: command.commandId,
      evaluate: (view) => _evaluateRoomEntryCommand(
        context: context,
        actorUid: identity.uid,
        request: request,
        command: command,
        material: material,
        view: view,
        rulesCatalogRepository: _rulesCatalogRepository,
      ),
    );
    final decision = transaction.decision;
    return AuthorityExecutionResult<api.AuthorityCommandReply>(
      value: decision.reply,
      outcome: decision.outcome,
      reason: decision.reason,
      metrics: transaction.metrics,
    );
  }

  FirstPlayableStartMaterialFactory _requireStartMaterialFactory() {
    final factory = _startMaterialFactory;
    if (factory == null) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'startMaterialUnavailable',
      );
    }
    return factory;
  }

  @override
  Future<api.AuthorityReconnectReply> reconnect({
    required IngressContext context,
    required VerifiedIdentity identity,
    required api.AuthorityReconnectRequest request,
  }) async {
    final read = await _store.readGame(
      gameId: request.gameId,
      commandId: request.uncertainCommand?.commandId,
    );
    _rulesCatalogRepository.catalogForGame(read.view.publicState);
    final playerId = _requirePlayerId(read.view, identity.uid);
    final uncertain = request.uncertainCommand;
    final stored = read.view.storedReceipt;
    final durableReceipt = stored == null
        ? null
        : stored.actorUid == identity.uid
        ? stored.receipt
        : reconnect_planner.DurableCommandReceipt(
            commandId: stored.receipt.commandId,
            inputHashVersion: stored.receipt.inputHashVersion,
            inputHash: List<String>.filled(64, '0').join(),
            publicResult: stored.receipt.publicResult,
          );
    final plan = reconnect_planner.AuthorityReconnectPlanner.reconcile(
      authenticatedActorUid: identity.uid,
      actorPlayerId: playerId,
      memberUidByPlayerId: read.view.memberUidByPlayerId,
      clientStateVersion: request.observedStateVersion,
      authoritativeState: read.view.publicState,
      uncertainCommand: uncertain == null
          ? null
          : reconnect_planner.UncertainCommandIdentity(
              commandId: uncertain.commandId,
              inputHashVersion: uncertain.inputHashVersion,
              inputHash: uncertain.inputHash,
            ),
      durableReceipt: durableReceipt,
    );
    return FirstPlayableResponseAdapter.reconnect(plan: plan, request: request);
  }

  @override
  Future<api.AuthorityPublicSnapshot> readPublicGame({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String gameId,
  }) async {
    final read = await _store.readGame(gameId: gameId);
    _rulesCatalogRepository.catalogForGame(read.view.publicState);
    _requirePlayerId(read.view, identity.uid);
    return api.AuthorityPublicSnapshot(read.view.publicState.toJson());
  }

  @override
  Future<api.AuthorityPublicRoomSnapshot> readPublicRoom({
    required IngressContext context,
    required VerifiedIdentity identity,
    required String roomId,
  }) async {
    final store = _store is FirstPlayableRoomSnapshotStore
        ? _store as FirstPlayableRoomSnapshotStore
        : throw const FirstPlayableAuthorityExecutorViolation(
            'roomSnapshotStoreUnavailable',
          );
    final read = await store.readRoom(roomId: roomId);
    _rulesCatalogRepository.catalogForRoom(
      rulesVersion: read.view.rulesVersion,
      presetId: read.view.presetId,
    );
    final actor = read.view.members.singleWhere(
      (member) => member.uid == identity.uid,
      orElse: () =>
          throw const MembershipAuthorizationException('notRoomMember'),
    );
    final hostPlayerId = read.view.members
        .singleWhere((member) => member.uid == read.view.hostUid)
        .playerId;
    return api.AuthorityPublicRoomSnapshot(<String, Object?>{
      'schemaVersion': 1,
      'roomId': read.view.roomId,
      'roomVersion': read.view.roomVersion,
      'status': read.view.status,
      'hostPlayerId': hostPlayerId,
      'actorPlayerId': actor.playerId,
      'presetId': read.view.presetId,
      'rulesVersion': read.view.rulesVersion,
      'members': <Object?>[
        for (final member in read.view.members)
          <String, Object?>{
            'playerId': member.playerId,
            'kind': member.kind.name,
            'ready': member.ready,
          },
      ],
    });
  }

  static FirstPlayableGameTransactionDecision _evaluateGameCommand({
    required IngressContext context,
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required GameCommand command,
    required FirstPlayableGameTransactionView view,
    required RulesCatalog catalog,
  }) {
    final prior = view.storedReceipt;
    if (prior != null) {
      final exactDuplicate =
          prior.actorUid == actorUid &&
          prior.receipt.commandId == command.commandId &&
          prior.receipt.inputHashVersion == request.inputHashVersion &&
          prior.receipt.inputHash == request.inputHash;
      if (exactDuplicate) {
        return FirstPlayableGameTransactionDecision(
          reply: FirstPlayableResponseAdapter.duplicate(prior.receipt),
          outcome: AuthorityOutcome.duplicate,
          reason: AuthorityReason.duplicateCommand,
        );
      }
      final version = view.publicState.header.stateVersion;
      return FirstPlayableGameTransactionDecision(
        reply: api.AuthorityCommandReply(
          commandId: command.commandId,
          status: api.AuthorityCommandStatus.rejected,
          versionBefore: version,
          versionAfter: version,
          errorCode: 'commandIdCollision',
          publicResult: <String, Object?>{
            'commandId': command.commandId,
            'status': 'rejected',
            'stateVersionBefore': version,
            'stateVersionAfter': version,
            'errorCode': 'commandIdCollision',
          },
        ),
        outcome: AuthorityOutcome.collision,
        reason: AuthorityReason.commandIdCollision,
      );
    }

    final evaluation = switch (command.type) {
      GameCommandType.rollDice => _evaluateRoll(
        context: context,
        actorUid: actorUid,
        command: command,
        view: view,
        catalog: catalog,
      ),
      GameCommandType.buyProperty ||
      GameCommandType.declineProperty ||
      GameCommandType.placeBid ||
      GameCommandType.passAuction => _evaluateBuyAuction(
        context: context,
        actorUid: actorUid,
        command: command,
        view: view,
        catalog: catalog,
      ),
      _ => throw FirstPlayableAuthorityExecutorViolation(
        'unsupportedGameCommand:${command.type.wireValue}',
      ),
    };
    return _persistableDecision(
      actorUid: actorUid,
      request: request,
      evaluation: evaluation,
    );
  }

  static FirstPlayableRoomTransactionDecision _evaluateRoomCommand({
    required IngressContext context,
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required RoomCommand command,
    required FirstPlayableRoomTransactionView view,
    required RulesCatalog catalog,
    required FirstPlayableStartMaterial? startMaterial,
  }) {
    final prior = view.storedReceipt;
    if (prior != null) {
      final exactDuplicate =
          prior.actorUid == actorUid &&
          prior.receipt.commandId == command.commandId &&
          prior.receipt.inputHashVersion == request.inputHashVersion &&
          prior.receipt.inputHash == request.inputHash;
      if (exactDuplicate) {
        return FirstPlayableRoomTransactionDecision(
          reply: FirstPlayableResponseAdapter.duplicate(prior.receipt),
          outcome: AuthorityOutcome.duplicate,
          reason: AuthorityReason.duplicateCommand,
        );
      }
      return _roomCollision(command, view.roomVersion);
    }
    if (view.roomId != command.payload['roomId']) {
      throw const FirstPlayableAuthorityExecutorViolation('roomIdMismatch');
    }
    _requireRoomMember(view, actorUid);
    if (view.status != 'open' ||
        command.expectedRoomVersion != view.roomVersion) {
      return _persistableRoomDecision(
        actorUid: actorUid,
        request: request,
        reply: _roomRejection(command, view.roomVersion, 'staleRoomVersion'),
        reason: AuthorityReason.staleVersion,
      );
    }

    return switch (command.type) {
      RoomCommandType.setReady => _evaluateSetReady(
        actorUid: actorUid,
        request: request,
        command: command,
        view: view,
      ),
      RoomCommandType.startGame => _evaluateStartGame(
        context: context,
        actorUid: actorUid,
        request: request,
        command: command,
        view: view,
        startMaterial: startMaterial!,
        catalog: catalog,
      ),
      _ => throw FirstPlayableAuthorityExecutorViolation(
        'unsupportedRoomCommand:${command.type.wireValue}',
      ),
    };
  }

  static FirstPlayableRoomEntryTransactionDecision _evaluateRoomEntryCommand({
    required IngressContext context,
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required RoomCommand command,
    required FirstPlayableRoomEntryMaterial material,
    required FirstPlayableRoomEntryTransactionView view,
    required FirstPlayableRulesCatalogRepository rulesCatalogRepository,
  }) {
    final prior = view.storedReceipt;
    if (prior != null) {
      final exactDuplicate =
          prior.actorUid == actorUid &&
          prior.receipt.commandId == command.commandId &&
          prior.receipt.inputHashVersion == request.inputHashVersion &&
          prior.receipt.inputHash == request.inputHash &&
          prior.roomEntryCodeHash == material.codeHash;
      if (!exactDuplicate) {
        return _roomEntryCollision(command, _roomEntryVersion(view));
      }
      final durable = FirstPlayableResponseAdapter.duplicate(prior.receipt);
      return FirstPlayableRoomEntryTransactionDecision(
        reply: command.type == RoomCommandType.createRoom
            ? api.AuthorityCommandReply(
                commandId: durable.commandId,
                status: durable.status,
                versionBefore: durable.versionBefore,
                versionAfter: durable.versionAfter,
                errorCode: durable.errorCode,
                publicResult: <String, Object?>{
                  ...durable.publicResult,
                  'roomCode': material.roomCode,
                },
              )
            : durable,
        outcome: AuthorityOutcome.duplicate,
        reason: AuthorityReason.duplicateCommand,
      );
    }

    return switch (material.kind) {
      FirstPlayableRoomEntryKind.create => _evaluateCreateRoom(
        context: context,
        actorUid: actorUid,
        request: request,
        command: command,
        material: material,
        view: view,
        rulesCatalogRepository: rulesCatalogRepository,
      ),
      FirstPlayableRoomEntryKind.join => _evaluateJoinRoom(
        context: context,
        actorUid: actorUid,
        request: request,
        command: command,
        material: material,
        view: view,
        rulesCatalogRepository: rulesCatalogRepository,
      ),
    };
  }

  static FirstPlayableRoomEntryTransactionDecision _evaluateCreateRoom({
    required IngressContext context,
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required RoomCommand command,
    required FirstPlayableRoomEntryMaterial material,
    required FirstPlayableRoomEntryTransactionView view,
    required FirstPlayableRulesCatalogRepository rulesCatalogRepository,
  }) {
    final locator = view.locator;
    if (locator != null &&
        locator.expiresAt.isAfter(context.requestReceivedAt)) {
      return _persistableRoomEntryRejection(
        actorUid: actorUid,
        request: request,
        command: command,
        material: material,
        version: 0,
        errorCode: 'roomCodeUnavailable',
      );
    }
    final roomId = material.roomId!;
    final expiresAt = material.expiresAt!.toUtc();
    if (!expiresAt.isAfter(context.requestReceivedAt)) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'roomEntryExpiryInvalid',
      );
    }
    final presetDraft = command.payload['presetDraft']! as Map<String, Object?>;
    final presetId = presetDraft['presetId'];
    if (presetDraft.length != 1 || presetId is! String || presetId.isEmpty) {
      return _persistableRoomEntryRejection(
        actorUid: actorUid,
        request: request,
        command: command,
        material: material,
        version: 0,
        errorCode: 'invalidPresetDraft',
      );
    }
    final members = <ReadyRoomMember>[
      ReadyRoomMember(
        uid: actorUid,
        playerId: material.playerId,
        kind: PlayerKind.human,
        ready: false,
      ),
    ];
    final catalog = rulesCatalogRepository.catalogForNewRoom(
      presetId: presetId,
    );
    try {
      catalog.resolvePreset(presetId, members.length);
    } on RulesCatalogViolation {
      return _persistableRoomEntryRejection(
        actorUid: actorUid,
        request: request,
        command: command,
        material: material,
        version: 0,
        errorCode: 'invalidPresetDraft',
      );
    }
    final mutation = FirstPlayableRoomEntryMutation(
      kind: material.kind,
      codeHash: material.codeHash,
      roomId: roomId,
      roomVersion: 1,
      hostUid: actorUid,
      presetId: presetId,
      rulesVersion: catalog.rulesVersion,
      membersAfter: members,
      updatedAt: context.requestReceivedAt,
      expiresAt: expiresAt,
    );
    return _persistableRoomEntryAccepted(
      actorUid: actorUid,
      request: request,
      command: command,
      material: material,
      mutation: mutation,
      versionBefore: 0,
      roomCode: material.roomCode,
    );
  }

  static FirstPlayableRoomEntryTransactionDecision _evaluateJoinRoom({
    required IngressContext context,
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required RoomCommand command,
    required FirstPlayableRoomEntryMaterial material,
    required FirstPlayableRoomEntryTransactionView view,
    required FirstPlayableRulesCatalogRepository rulesCatalogRepository,
  }) {
    final locator = view.locator;
    final room = view.room;
    if (locator == null ||
        !locator.expiresAt.isAfter(context.requestReceivedAt) ||
        room == null ||
        room.roomId != locator.roomId ||
        room.status != 'open') {
      return _persistableRoomEntryRejection(
        actorUid: actorUid,
        request: request,
        command: command,
        material: material,
        version: room?.roomVersion ?? 0,
        errorCode: 'roomUnavailable',
      );
    }
    if (room.members.any((member) => member.uid == actorUid)) {
      return _persistableRoomEntryRejection(
        actorUid: actorUid,
        request: request,
        command: command,
        material: material,
        version: room.roomVersion,
        errorCode: 'alreadyMember',
      );
    }
    final members = <ReadyRoomMember>[
      ...room.members,
      ReadyRoomMember(
        uid: actorUid,
        playerId: material.playerId,
        kind: PlayerKind.human,
        ready: false,
      ),
    ];
    final catalog = rulesCatalogRepository.catalogForRoom(
      rulesVersion: room.rulesVersion,
      presetId: room.presetId,
    );
    try {
      catalog.resolvePreset(room.presetId, members.length);
    } on RulesCatalogViolation {
      return _persistableRoomEntryRejection(
        actorUid: actorUid,
        request: request,
        command: command,
        material: material,
        version: room.roomVersion,
        errorCode: 'roomCapacityReached',
      );
    }
    final mutation = FirstPlayableRoomEntryMutation(
      kind: material.kind,
      codeHash: material.codeHash,
      roomId: room.roomId,
      roomVersion: room.roomVersion + 1,
      hostUid: room.hostUid,
      presetId: room.presetId,
      rulesVersion: room.rulesVersion,
      membersAfter: members,
    );
    return _persistableRoomEntryAccepted(
      actorUid: actorUid,
      request: request,
      command: command,
      material: material,
      mutation: mutation,
      versionBefore: room.roomVersion,
    );
  }

  static FirstPlayableRoomEntryTransactionDecision
  _persistableRoomEntryAccepted({
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required RoomCommand command,
    required FirstPlayableRoomEntryMaterial material,
    required FirstPlayableRoomEntryMutation mutation,
    required int versionBefore,
    String? roomCode,
  }) {
    final safeSnapshot = <String, Object?>{
      'roomId': mutation.roomId,
      'roomVersion': mutation.roomVersion,
      'status': 'open',
      'presetId': mutation.presetId,
      'actorPlayerId': material.playerId,
      'readyByPlayerId': <String, Object?>{
        for (final member in mutation.membersAfter)
          member.playerId: member.ready,
      },
    };
    final durableResult = <String, Object?>{
      'commandId': command.commandId,
      'status': 'accepted',
      'stateVersionBefore': versionBefore,
      'stateVersionAfter': mutation.roomVersion,
      'roomId': mutation.roomId,
      'roomVersion': mutation.roomVersion,
      'actorPlayerId': material.playerId,
      'roomSnapshot': safeSnapshot,
    };
    final replyResult = <String, Object?>{
      ...durableResult,
      'roomCode': ?roomCode,
    };
    final reply = api.AuthorityCommandReply(
      commandId: command.commandId,
      status: api.AuthorityCommandStatus.accepted,
      versionBefore: versionBefore,
      versionAfter: mutation.roomVersion,
      publicResult: replyResult,
    );
    return FirstPlayableRoomEntryTransactionDecision(
      reply: reply,
      outcome: AuthorityOutcome.success,
      reason: AuthorityReason.none,
      mutation: mutation,
      receiptToPersist: StoredAuthorityCommandReceipt(
        actorUid: actorUid,
        roomEntryCodeHash: material.codeHash,
        receipt: reconnect_planner.DurableCommandReceipt(
          commandId: command.commandId,
          inputHashVersion: request.inputHashVersion,
          inputHash: request.inputHash,
          publicResult: durableResult,
        ),
      ),
    );
  }

  static FirstPlayableRoomEntryTransactionDecision
  _persistableRoomEntryRejection({
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required RoomCommand command,
    required FirstPlayableRoomEntryMaterial material,
    required int version,
    required String errorCode,
  }) {
    final result = <String, Object?>{
      'commandId': command.commandId,
      'status': 'rejected',
      'stateVersionBefore': version,
      'stateVersionAfter': version,
      'errorCode': errorCode,
    };
    final reply = api.AuthorityCommandReply(
      commandId: command.commandId,
      status: api.AuthorityCommandStatus.rejected,
      versionBefore: version,
      versionAfter: version,
      errorCode: errorCode,
      publicResult: result,
    );
    return FirstPlayableRoomEntryTransactionDecision(
      reply: reply,
      outcome: AuthorityOutcome.rejected,
      reason: AuthorityReason.none,
      receiptToPersist: StoredAuthorityCommandReceipt(
        actorUid: actorUid,
        roomEntryCodeHash: material.codeHash,
        receipt: reconnect_planner.DurableCommandReceipt(
          commandId: command.commandId,
          inputHashVersion: request.inputHashVersion,
          inputHash: request.inputHash,
          publicResult: result,
        ),
      ),
    );
  }

  static FirstPlayableRoomEntryTransactionDecision _roomEntryCollision(
    RoomCommand command,
    int version,
  ) => FirstPlayableRoomEntryTransactionDecision(
    reply: _roomRejection(command, version, 'commandIdCollision'),
    outcome: AuthorityOutcome.collision,
    reason: AuthorityReason.commandIdCollision,
  );

  static int _roomEntryVersion(FirstPlayableRoomEntryTransactionView view) {
    final version =
        view.storedReceipt?.receipt.publicResult['stateVersionAfter'];
    return version is int && version >= 0
        ? version
        : view.room?.roomVersion ?? 0;
  }

  static FirstPlayableRoomTransactionDecision _evaluateSetReady({
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required RoomCommand command,
    required FirstPlayableRoomTransactionView view,
  }) {
    final ready = command.payload['ready']! as bool;
    final membersAfter = <ReadyRoomMember>[
      for (final member in view.members)
        ReadyRoomMember(
          uid: member.uid,
          playerId: member.playerId,
          kind: member.kind,
          ready: member.uid == actorUid ? ready : member.ready,
          botPolicyId: member.botPolicyId,
        ),
    ];
    final versionAfter = view.roomVersion + 1;
    final publicResult = <String, Object?>{
      'commandId': command.commandId,
      'status': 'accepted',
      'stateVersionBefore': view.roomVersion,
      'stateVersionAfter': versionAfter,
      'roomId': view.roomId,
      'roomVersionBefore': view.roomVersion,
      'roomVersionAfter': versionAfter,
      'readyByPlayerId': <String, Object?>{
        for (final member in membersAfter) member.playerId: member.ready,
      },
    };
    final reply = api.AuthorityCommandReply(
      commandId: command.commandId,
      status: api.AuthorityCommandStatus.accepted,
      versionBefore: view.roomVersion,
      versionAfter: versionAfter,
      publicResult: publicResult,
    );
    return _persistableRoomDecision(
      actorUid: actorUid,
      request: request,
      reply: reply,
      membersAfter: membersAfter,
    );
  }

  static FirstPlayableRoomTransactionDecision _evaluateStartGame({
    required IngressContext context,
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required RoomCommand command,
    required FirstPlayableRoomTransactionView view,
    required FirstPlayableStartMaterial startMaterial,
    required RulesCatalog catalog,
  }) {
    try {
      final plan = ReadyStartPlanner.plan(
        command: command,
        authenticatedActorUid: actorUid,
        hostUid: view.hostUid,
        gameId: startMaterial.gameId,
        presetId: view.presetId,
        members: view.members,
        catalog: catalog,
        secureSeed: startMaterial.seed,
      );
      final publicResult = <String, Object?>{
        'commandId': command.commandId,
        'status': 'accepted',
        'stateVersionBefore': view.roomVersion,
        'stateVersionAfter': plan.roomVersionAfter,
        'roomId': view.roomId,
        'roomVersionBefore': view.roomVersion,
        'roomVersionAfter': plan.roomVersionAfter,
        ...plan.safeResultSummary,
      };
      final reply = api.AuthorityCommandReply(
        commandId: command.commandId,
        status: api.AuthorityCommandStatus.accepted,
        versionBefore: view.roomVersion,
        versionAfter: plan.roomVersionAfter,
        publicResult: publicResult,
      );
      return _persistableRoomDecision(
        actorUid: actorUid,
        request: request,
        reply: reply,
        startPlan: plan,
        startMemberUidByPlayerId: <String, String>{
          for (final member in view.members) member.playerId: member.uid,
        },
      );
    } on ReadyStartViolation catch (error) {
      return _persistableRoomDecision(
        actorUid: actorUid,
        request: request,
        reply: _roomRejection(command, view.roomVersion, error.code),
      );
    }
  }

  static FirstPlayableRoomTransactionDecision _persistableRoomDecision({
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required api.AuthorityCommandReply reply,
    AuthorityReason reason = AuthorityReason.none,
    List<ReadyRoomMember>? membersAfter,
    ReadyStartPlan? startPlan,
    Map<String, String>? startMemberUidByPlayerId,
  }) => FirstPlayableRoomTransactionDecision(
    reply: reply,
    outcome: reply.status == api.AuthorityCommandStatus.accepted
        ? AuthorityOutcome.success
        : reason == AuthorityReason.staleVersion
        ? AuthorityOutcome.stale
        : AuthorityOutcome.rejected,
    reason: reason,
    membersAfter: membersAfter,
    startPlan: startPlan,
    startMemberUidByPlayerId: startMemberUidByPlayerId,
    receiptToPersist: StoredAuthorityCommandReceipt(
      actorUid: actorUid,
      receipt: reconnect_planner.DurableCommandReceipt(
        commandId: reply.commandId,
        inputHashVersion: request.inputHashVersion,
        inputHash: request.inputHash,
        publicResult: reply.publicResult,
      ),
    ),
  );

  static FirstPlayableRoomTransactionDecision _roomCollision(
    RoomCommand command,
    int version,
  ) => FirstPlayableRoomTransactionDecision(
    reply: _roomRejection(command, version, 'commandIdCollision'),
    outcome: AuthorityOutcome.collision,
    reason: AuthorityReason.commandIdCollision,
  );

  static api.AuthorityCommandReply _roomRejection(
    RoomCommand command,
    int version,
    String errorCode,
  ) => api.AuthorityCommandReply(
    commandId: command.commandId,
    status: api.AuthorityCommandStatus.rejected,
    versionBefore: version,
    versionAfter: version,
    errorCode: errorCode,
    publicResult: <String, Object?>{
      'commandId': command.commandId,
      'status': 'rejected',
      'stateVersionBefore': version,
      'stateVersionAfter': version,
      'roomVersionBefore': version,
      'roomVersionAfter': version,
      'errorCode': errorCode,
    },
  );

  static ReadyRoomMember _requireRoomMember(
    FirstPlayableRoomTransactionView view,
    String actorUid,
  ) {
    final matches = view.members
        .where((member) => member.uid == actorUid)
        .toList(growable: false);
    if (matches.length != 1) {
      throw const MembershipAuthorizationException('not_a_member');
    }
    return matches.single;
  }

  static _EvaluatedGameCommand _evaluateRoll({
    required IngressContext context,
    required String actorUid,
    required GameCommand command,
    required FirstPlayableGameTransactionView view,
    required RulesCatalog catalog,
  }) {
    final privateRng = view.privateRng;
    if (privateRng == null) {
      throw const FirstPlayableAuthorityExecutorViolation(
        'privateRngUnavailable',
      );
    }
    final evaluation = AuthorityRollMovementPlanner.evaluate(
      command: command,
      authenticatedActorUid: actorUid,
      memberUidByPlayerId: view.memberUidByPlayerId,
      state: view.publicState,
      catalog: catalog,
      privateSnapshot: privateRng,
      transitionTime: context.requestReceivedAt,
    );
    final reply = FirstPlayableResponseAdapter.rollMovement(evaluation);
    return switch (evaluation) {
      AuthorityRollMovementAccepted(:final plan) => _EvaluatedGameCommand(
        reply: reply,
        publicStateAfter: plan.stateAfter,
        privateRngAfter: plan.successorPrivateState,
      ),
      AuthorityRollMovementRejected() => _EvaluatedGameCommand(reply: reply),
    };
  }

  static _EvaluatedGameCommand _evaluateBuyAuction({
    required IngressContext context,
    required String actorUid,
    required GameCommand command,
    required FirstPlayableGameTransactionView view,
    required RulesCatalog catalog,
  }) {
    final evaluation = AuthorityBuyAuctionPlanner.evaluateHuman(
      command: command,
      authenticatedActorUid: actorUid,
      memberUidByPlayerId: view.memberUidByPlayerId,
      state: view.publicState,
      catalog: catalog,
      requestReceivedAt: context.requestReceivedAt,
    );
    final reply = FirstPlayableResponseAdapter.buyAuction(evaluation);
    return switch (evaluation) {
      AuthorityBuyAuctionAccepted(:final plan) => _EvaluatedGameCommand(
        reply: reply,
        publicStateAfter: plan.stateAfter,
      ),
      AuthorityBuyAuctionRejected() => _EvaluatedGameCommand(reply: reply),
      AuthorityBuyAuctionNoOp() =>
        throw const FirstPlayableAuthorityExecutorViolation(
          'unexpectedHumanNoOp',
        ),
    };
  }

  static FirstPlayableGameTransactionDecision _persistableDecision({
    required String actorUid,
    required api.AuthorityCommandRequest request,
    required _EvaluatedGameCommand evaluation,
  }) {
    final reply = evaluation.reply;
    final receipt = StoredAuthorityCommandReceipt(
      actorUid: actorUid,
      receipt: reconnect_planner.DurableCommandReceipt(
        commandId: reply.commandId,
        inputHashVersion: request.inputHashVersion,
        inputHash: request.inputHash,
        publicResult: reply.publicResult,
      ),
    );
    final reason = switch (reply.errorCode) {
      'staleVersion' => AuthorityReason.staleVersion,
      'decisionClosed' => AuthorityReason.decisionClosed,
      _ => AuthorityReason.none,
    };
    return FirstPlayableGameTransactionDecision(
      reply: reply,
      outcome: reply.status == api.AuthorityCommandStatus.accepted
          ? AuthorityOutcome.success
          : reason == AuthorityReason.staleVersion
          ? AuthorityOutcome.stale
          : AuthorityOutcome.rejected,
      reason: reason,
      publicStateAfter: evaluation.publicStateAfter,
      privateRngAfter: evaluation.privateRngAfter,
      receiptToPersist: receipt,
    );
  }

  static String _requirePlayerId(
    FirstPlayableGameTransactionView view,
    String actorUid,
  ) {
    final matches = view.memberUidByPlayerId.entries
        .where((entry) => entry.value == actorUid)
        .map((entry) => entry.key)
        .toList(growable: false);
    if (matches.length != 1) {
      throw const MembershipAuthorizationException('not_a_member');
    }
    return matches.single;
  }
}

final class _EvaluatedGameCommand {
  const _EvaluatedGameCommand({
    required this.reply,
    this.publicStateAfter,
    this.privateRngAfter,
  });

  final api.AuthorityCommandReply reply;
  final PublicGameState? publicStateAfter;
  final AuthorityPrivateRngSnapshot? privateRngAfter;
}
