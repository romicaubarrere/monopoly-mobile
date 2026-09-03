import 'dart:async';
import 'dart:io';

import 'client_authority.dart';
import 'client_authority_adapter.dart';
import 'client_authority_session.dart';
import 'first_playable_binding.dart';
import 'first_playable_commands.dart';
import 'first_playable_context.dart';
import 'first_playable_device_storage.dart';
import 'first_playable_session_locator.dart';
import 'http_authority_transport.dart';

/// Flutter-facing composition root for the VP0 Authority vertical.
///
/// The application supplies authentication, durable command identity/storage,
/// the Authority origin and a preset id. This class owns the remaining wire,
/// session, confirmed-context and snapshot plumbing; it never evaluates Engine
/// rules or exposes Authority-private state.
final class FirstPlayableAuthorityClient
    implements FirstPlayableAuthorityBinding {
  factory FirstPlayableAuthorityClient.withTransport({
    required AuthorityWireTransport transport,
    required PendingAuthorityCommandStore pendingStore,
    required FirstPlayableSessionLocatorStore sessionLocatorStore,
    required AuthorityCommandIdSource commandIds,
    required String clientInstanceId,
    required String presetId,
  }) => _compose(
    transport: transport,
    pendingStore: pendingStore,
    sessionLocatorStore: sessionLocatorStore,
    commandIds: commandIds,
    clientInstanceId: clientInstanceId,
    presetId: presetId,
  );

  factory FirstPlayableAuthorityClient.http({
    required Uri baseUri,
    required AuthorityIdTokenProvider idTokenProvider,
    required PendingAuthorityCommandStore pendingStore,
    required FirstPlayableSessionLocatorStore sessionLocatorStore,
    required AuthorityCommandIdSource commandIds,
    required String clientInstanceId,
    required String presetId,
    Duration snapshotPollInterval = const Duration(seconds: 1),
    HttpClient? httpClient,
  }) {
    final transport = HttpAuthorityWireTransport(
      baseUri: baseUri,
      idTokenProvider: idTokenProvider,
      snapshotPollInterval: snapshotPollInterval,
      httpClient: httpClient,
    );
    return _compose(
      transport: transport,
      pendingStore: pendingStore,
      sessionLocatorStore: sessionLocatorStore,
      commandIds: commandIds,
      clientInstanceId: clientInstanceId,
      presetId: presetId,
      closeTransport: transport.close,
    );
  }

  /// HTTP composition using the single durable key-value port Flutter owns.
  factory FirstPlayableAuthorityClient.httpWithDeviceStorage({
    required Uri baseUri,
    required AuthorityIdTokenProvider idTokenProvider,
    required FirstPlayableAuthorityDeviceStorage deviceStorage,
    required AuthorityCommandIdSource commandIds,
    required String clientInstanceId,
    required String presetId,
    Duration snapshotPollInterval = const Duration(seconds: 1),
    HttpClient? httpClient,
  }) => FirstPlayableAuthorityClient.http(
    baseUri: baseUri,
    idTokenProvider: idTokenProvider,
    pendingStore: deviceStorage.pendingCommands,
    sessionLocatorStore: deviceStorage.sessionLocator,
    commandIds: commandIds,
    clientInstanceId: clientInstanceId,
    presetId: presetId,
    snapshotPollInterval: snapshotPollInterval,
    httpClient: httpClient,
  );

  FirstPlayableAuthorityClient._(
    this._session,
    this._context,
    this._snapshots,
    this._sessionLocatorStore,
    this._binding,
    this._closeTransport,
  ) {
    _stateSubscription = _session.states.listen(_acceptSessionState);
  }

  final AuthorityClientSession _session;
  final FirstPlayableAuthorityContext _context;
  final WireAuthorityClient _snapshots;
  final FirstPlayableSessionLocatorStore _sessionLocatorStore;
  final SessionFirstPlayableAuthorityBinding _binding;
  final void Function({bool force})? _closeTransport;
  late final StreamSubscription<AuthoritySessionState> _stateSubscription;
  String? _watchedGameId;
  String? _snapshotContractErrorCode;

  AuthoritySessionState get state => _session.state;
  Stream<AuthoritySessionState> get states => _session.states;

  /// Transient six-character code returned only by an accepted CreateRoom ACK.
  ///
  /// The code is intentionally not reconstructed from Firestore or persisted in
  /// the client composition root. Presentation may show it so another device
  /// can join the room, then discard it.
  String? get latestCreatedRoomCode {
    final value = _session.state.reply?.publicResult['roomCode'];
    if (value == null) return null;
    if (value is! String || !RegExp(r'^[A-Z0-9]{6}$').hasMatch(value)) {
      throw const ClientAuthorityContractViolation('invalidAuthorityRoomCode');
    }
    return value;
  }

  /// Refreshes the authenticated public lobby snapshot for the confirmed room.
  ///
  /// Only the already-validated public room contract is returned. UID mappings,
  /// room secrets, catalog payloads and any other private state remain absent.
  Future<AuthorityPublicRoomSnapshot> refreshConfirmedRoom() async {
    final snapshot = await _snapshots.watchRoom(_context.roomId).first;
    _context.replacePublicRoomSnapshot(snapshot);
    return snapshot;
  }

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async {
    final snapshotError = _snapshotContractErrorCode;
    if (snapshotError != null) {
      return FirstPlayableAuthorityResult(
        outcome: FirstPlayableAuthorityOutcome.blocked,
        safeErrorCode: snapshotError,
      );
    }

    final result = await _binding.perform(action, input: input);
    final startsGame =
        result.accepted && action == FirstPlayableAuthorityAction.startGame;
    final resumesGame =
        action == FirstPlayableAuthorityAction.reconnect &&
        result.outcome != FirstPlayableAuthorityOutcome.blocked;
    if (startsGame || resumesGame) {
      _watchConfirmedGame();
    }
    if (result.accepted) await _saveConfirmedLocator();
    return result;
  }

  /// Restores public context after process death from authenticated snapshots.
  Future<FirstPlayableAuthorityResult> restore() async {
    try {
      final locator = await _sessionLocatorStore.load();
      if (locator == null) {
        return const FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.blocked,
          safeErrorCode: 'confirmedSessionUnavailable',
        );
      }
      final roomSnapshot = await _snapshots.watchRoom(locator.roomId).first;
      _context.restorePublicRoomSnapshot(roomSnapshot);
      final gameId = locator.gameId;
      if (gameId != null) {
        final gameSnapshot = await _snapshots.watchGame(gameId).first;
        _context.replacePublicSnapshot(gameSnapshot);
        _session.restorePublicSnapshot(gameSnapshot);
        _watchConfirmedGame();
      }
      _snapshotContractErrorCode = null;
      return const FirstPlayableAuthorityResult(
        outcome: FirstPlayableAuthorityOutcome.accepted,
      );
    } on ClientAuthorityContractViolation catch (error) {
      _snapshotContractErrorCode = error.code;
      return FirstPlayableAuthorityResult(
        outcome: FirstPlayableAuthorityOutcome.blocked,
        safeErrorCode: error.code,
      );
    } on Object {
      _snapshotContractErrorCode = 'sessionRestoreUnavailable';
      return const FirstPlayableAuthorityResult(
        outcome: FirstPlayableAuthorityOutcome.blocked,
        safeErrorCode: 'sessionRestoreUnavailable',
      );
    }
  }

  Future<void> close({bool forceTransport = false}) async {
    await _stateSubscription.cancel();
    await _session.close();
    _closeTransport?.call(force: forceTransport);
  }

  void _acceptSessionState(AuthoritySessionState state) {
    final snapshot = state.snapshot;
    if (snapshot == null || _snapshotContractErrorCode != null) return;
    try {
      _context.replacePublicSnapshot(snapshot);
    } on ClientAuthorityContractViolation catch (error) {
      _snapshotContractErrorCode = error.code;
    } on Object {
      _snapshotContractErrorCode = 'invalidAuthoritySnapshot';
    }
  }

  void _watchConfirmedGame() {
    try {
      final gameId = _context.gameId;
      if (_watchedGameId == gameId) return;
      _watchedGameId = gameId;
      _session.watch(gameId);
    } on ClientAuthorityContractViolation catch (error) {
      _snapshotContractErrorCode = error.code;
    }
  }

  Future<void> _saveConfirmedLocator() async {
    try {
      final roomId = _context.roomId;
      String? gameId;
      try {
        gameId = _context.gameId;
      } on ClientAuthorityContractViolation {
        // A confirmed lobby legitimately has no game yet.
      }
      await _sessionLocatorStore.save(
        FirstPlayableSessionLocator(roomId: roomId, gameId: gameId),
      );
    } on ClientAuthorityContractViolation catch (error) {
      _snapshotContractErrorCode = error.code;
    } on Object {
      _snapshotContractErrorCode = 'sessionLocatorStoreUnavailable';
    }
  }
}

FirstPlayableAuthorityClient _compose({
  required AuthorityWireTransport transport,
  required PendingAuthorityCommandStore pendingStore,
  required FirstPlayableSessionLocatorStore sessionLocatorStore,
  required AuthorityCommandIdSource commandIds,
  required String clientInstanceId,
  required String presetId,
  void Function({bool force})? closeTransport,
}) {
  if (presetId.isEmpty || presetId.trim() != presetId) {
    throw const ClientAuthorityContractViolation('invalidPresetId');
  }
  final wireClient = WireAuthorityClient(transport);
  final session = AuthorityClientSession(
    gateway: wireClient,
    snapshots: wireClient,
    pendingStore: pendingStore,
  );
  final context = FirstPlayableAuthorityContext();
  final requests = ConfirmedFirstPlayableRequestResolver(
    commands: FirstPlayableAuthorityCommands(
      clientInstanceId: clientInstanceId,
      commandIds: commandIds,
    ),
    context: context,
    createRoomPresetDraft: <String, Object?>{'presetId': presetId},
  );
  return FirstPlayableAuthorityClient._(
    session,
    context,
    wireClient,
    sessionLocatorStore,
    SessionFirstPlayableAuthorityBinding(
      session: session,
      requests: requests,
      roomSnapshots: wireClient,
    ),
    closeTransport,
  );
}
