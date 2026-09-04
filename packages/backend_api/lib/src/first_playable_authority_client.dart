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
    Duration snapshotReadTimeout = const Duration(seconds: 10),
  }) => _compose(
    transport: transport,
    pendingStore: pendingStore,
    sessionLocatorStore: sessionLocatorStore,
    commandIds: commandIds,
    clientInstanceId: clientInstanceId,
    presetId: presetId,
    snapshotReadTimeout: snapshotReadTimeout,
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
    Duration snapshotRetryMaxDelay = const Duration(seconds: 30),
    Duration snapshotReadTimeout = const Duration(seconds: 10),
    HttpClient? httpClient,
  }) {
    final transport = HttpAuthorityWireTransport(
      baseUri: baseUri,
      idTokenProvider: idTokenProvider,
      snapshotPollInterval: snapshotPollInterval,
      snapshotRetryMaxDelay: snapshotRetryMaxDelay,
      httpClient: httpClient,
    );
    return _compose(
      transport: transport,
      pendingStore: pendingStore,
      sessionLocatorStore: sessionLocatorStore,
      commandIds: commandIds,
      clientInstanceId: clientInstanceId,
      presetId: presetId,
      snapshotReadTimeout: snapshotReadTimeout,
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
    Duration snapshotRetryMaxDelay = const Duration(seconds: 30),
    Duration snapshotReadTimeout = const Duration(seconds: 10),
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
    snapshotRetryMaxDelay: snapshotRetryMaxDelay,
    snapshotReadTimeout: snapshotReadTimeout,
    httpClient: httpClient,
  );

  FirstPlayableAuthorityClient._(
    this._session,
    this._context,
    this._snapshots,
    this._sessionLocatorStore,
    this._binding,
    this._closeTransport,
    this._snapshotReadTimeout,
  ) {
    _stateSubscription = _session.states.listen(_acceptSessionState);
  }

  final AuthorityClientSession _session;
  final FirstPlayableAuthorityContext _context;
  final WireAuthorityClient _snapshots;
  final FirstPlayableSessionLocatorStore _sessionLocatorStore;
  final SessionFirstPlayableAuthorityBinding _binding;
  final void Function({bool force})? _closeTransport;
  final Duration _snapshotReadTimeout;
  final StreamController<AuthorityPublicRoomSnapshot> _roomSnapshotEvents =
      StreamController<AuthorityPublicRoomSnapshot>.broadcast(sync: true);
  final StreamController<AuthorityPublicSnapshot> _gameSnapshotEvents =
      StreamController<AuthorityPublicSnapshot>.broadcast(sync: true);
  late final StreamSubscription<AuthoritySessionState> _stateSubscription;
  StreamSubscription<AuthorityPublicRoomSnapshot>? _roomSnapshotSubscription;
  AuthorityPublicRoomSnapshot? _confirmedRoomSnapshot;
  AuthorityPublicSnapshot? _confirmedGameSnapshot;
  String? _watchedRoomId;
  String? _watchedGameId;
  String? _snapshotContractErrorCode;
  String? _persistenceErrorCode;
  String? _roomSnapshotTransportErrorCode;
  String? _gameSnapshotTransportErrorCode;
  int _roomWatchGeneration = 0;
  int _gameWatchGeneration = 0;

  AuthoritySessionState get state => _session.state;
  Stream<AuthoritySessionState> get states => _session.states;

  /// Latest authenticated lobby replacement accepted for this device's room.
  ///
  /// The value is absent until Create/Join/Restore establishes a room and a
  /// public room read arrives. It contains no UID mapping or private state.
  AuthorityPublicRoomSnapshot? get confirmedRoomSnapshot =>
      _confirmedRoomSnapshot;

  /// Authenticated, monotonic public lobby replacements for the confirmed room.
  ///
  /// Consumers should combine this with [confirmedRoomSnapshot] because this
  /// is a broadcast stream and deliberately does not replay an old snapshot to
  /// a later subscriber.
  Stream<AuthorityPublicRoomSnapshot> get roomSnapshots =>
      _roomSnapshotEvents.stream;

  /// Latest authenticated public game replacement for the confirmed game.
  AuthorityPublicSnapshot? get confirmedGameSnapshot => _confirmedGameSnapshot;

  /// Whether a persisted command identity still needs an explicit Authority
  /// reconciliation after process recovery. The UI must not mint a second
  /// command while this remains true.
  bool get requiresReconciliation {
    final state = _session.state;
    if (state.pendingCommand == null) return false;
    return switch (state.status) {
      AuthoritySessionStatus.uncertain ||
      AuthoritySessionStatus.confirmed => true,
      AuthoritySessionStatus.blocked =>
        state.safeErrorCode == 'uncertainCommandPending' ||
            state.safeErrorCode == 'pendingCommandStoreUnavailable',
      AuthoritySessionStatus.idle ||
      AuthoritySessionStatus.sending ||
      AuthoritySessionStatus.rejected ||
      AuthoritySessionStatus.reconnecting => false,
    };
  }

  /// Authenticated, monotonic public game replacements for the confirmed game.
  ///
  /// A room replacement containing its Authority-issued `gameId` starts this
  /// stream for guests as well as the host that issued StartGame.
  Stream<AuthorityPublicSnapshot> get gameSnapshots =>
      _gameSnapshotEvents.stream;

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
    try {
      final snapshot = await _readRoomSnapshot(_context.roomId);
      _applyRoomSnapshot(snapshot, restartGameOnSameVersion: true);
      _watchConfirmedRoom();
      return _confirmedRoomSnapshot!;
    } on ClientAuthorityContractViolation catch (error) {
      _snapshotContractErrorCode = error.code;
      rethrow;
    }
  }

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async {
    final snapshotError =
        _snapshotContractErrorCode ??
        (action == FirstPlayableAuthorityAction.reconnect
            ? null
            : _roomSnapshotTransportErrorCode ??
                  _gameSnapshotTransportErrorCode);
    if (snapshotError != null) {
      return FirstPlayableAuthorityResult(
        outcome: FirstPlayableAuthorityOutcome.blocked,
        safeErrorCode: snapshotError,
      );
    }

    final result = await _binding.perform(action, input: input);
    final startsGame =
        result.accepted && action == FirstPlayableAuthorityAction.startGame;
    final reconcilesUncertainCommand =
        action == FirstPlayableAuthorityAction.reconnect &&
        result.outcome != FirstPlayableAuthorityOutcome.blocked;
    final entersRoom =
        result.accepted &&
        (action == FirstPlayableAuthorityAction.createRoom ||
            action == FirstPlayableAuthorityAction.joinRoom);
    if (entersRoom || reconcilesUncertainCommand) _watchConfirmedRoom();
    if (startsGame || reconcilesUncertainCommand) _watchConfirmedGame();
    if (result.accepted) {
      final locatorSaved = await _saveConfirmedLocator();
      final pendingAcknowledged =
          locatorSaved && await _session.acknowledgeConfirmedPendingCommand();
      if (!pendingAcknowledged) {
        return FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.blocked,
          safeErrorCode:
              _persistenceErrorCode ??
              _session.state.safeErrorCode ??
              'sessionLocatorStoreUnavailable',
        );
      }
    }
    return result;
  }

  /// Restores public context after process death from authenticated snapshots.
  Future<FirstPlayableAuthorityResult> restore() async {
    AuthorityCommandRequest? pending;
    try {
      pending = await _session.restorePendingCommand();
      // Room commands carry their complete durable identity and can be
      // explicitly replayed without waiting for a potentially unavailable
      // snapshot read. This is essential for Create/Join, which have no
      // locator at all until their lost ACK is reconciled.
      if (pending?.family == AuthorityCommandFamily.room) {
        return const FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.uncertain,
          safeErrorCode: 'pendingCommandRecoveryRequired',
        );
      }
      final locator = await _sessionLocatorStore.load();
      if (locator == null) {
        if (pending != null) {
          return const FirstPlayableAuthorityResult(
            outcome: FirstPlayableAuthorityOutcome.uncertain,
            safeErrorCode: 'pendingCommandRecoveryRequired',
          );
        }
        return const FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.blocked,
          safeErrorCode: 'confirmedSessionUnavailable',
        );
      }
      final roomSnapshot = await _readRoomSnapshot(locator.roomId);
      _applyRoomSnapshot(roomSnapshot, watchGame: false);
      // The room read is the authoritative routing source. A device locator
      // can be stale after a prior game, so it must never select a game that
      // the authenticated room snapshot does not currently name.
      final gameId = roomSnapshot.gameId;
      if (gameId != null) {
        final gameSnapshot = await _readGameSnapshot(gameId);
        _applyGameSnapshot(gameSnapshot);
        _session.restorePublicSnapshot(gameSnapshot);
        _watchConfirmedGame();
      }
      _watchConfirmedRoom();
      if (!await _saveConfirmedLocator()) {
        return FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.blocked,
          safeErrorCode:
              _persistenceErrorCode ?? 'sessionLocatorStoreUnavailable',
        );
      }
      _snapshotContractErrorCode = null;
      _persistenceErrorCode = null;
      if (pending != null) {
        // A game snapshot restore publishes confirmed state. Re-mark the
        // still-durable request afterward so the UI cannot issue a new
        // command before explicit reconciliation.
        await _session.restorePendingCommand();
        return const FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.uncertain,
          safeErrorCode: 'pendingCommandRecoveryRequired',
        );
      }
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
      if (pending != null) {
        return const FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.uncertain,
          safeErrorCode: 'pendingCommandRecoveryRequired',
        );
      }
      _snapshotContractErrorCode = 'sessionRestoreUnavailable';
      return const FirstPlayableAuthorityResult(
        outcome: FirstPlayableAuthorityOutcome.blocked,
        safeErrorCode: 'sessionRestoreUnavailable',
      );
    }
  }

  /// Bounds one-shot reads independently of the long-lived polling stream.
  ///
  /// A watch may retry transient availability indefinitely, but an explicit
  /// refresh, Start preflight or process restore must return control to the
  /// caller if Authority remains unavailable.
  Future<AuthorityPublicRoomSnapshot> _readRoomSnapshot(String roomId) =>
      _snapshots.watchRoom(roomId).timeout(_snapshotReadTimeout).first;

  Future<AuthorityPublicSnapshot> _readGameSnapshot(String gameId) =>
      _snapshots.watchGame(gameId).timeout(_snapshotReadTimeout).first;

  Future<void> close({bool forceTransport = false}) async {
    await _roomSnapshotSubscription?.cancel();
    await _stateSubscription.cancel();
    await _session.close();
    await _roomSnapshotEvents.close();
    await _gameSnapshotEvents.close();
    _closeTransport?.call(force: forceTransport);
  }

  void _acceptSessionState(AuthoritySessionState state) {
    final snapshot = state.snapshot;
    if (state.status != AuthoritySessionStatus.confirmed ||
        snapshot == null ||
        _snapshotContractErrorCode != null) {
      return;
    }
    try {
      _applyGameSnapshot(snapshot);
    } on ClientAuthorityContractViolation catch (error) {
      _snapshotContractErrorCode = error.code;
      _addGameSnapshotError(error);
    }
  }

  void _watchConfirmedRoom() {
    String? roomIdForReset;
    int? generationForReset;
    try {
      final roomId = _context.roomId;
      if (_watchedRoomId == roomId) return;
      _watchedRoomId = roomId;
      final generation = ++_roomWatchGeneration;
      roomIdForReset = roomId;
      generationForReset = generation;
      final previous = _roomSnapshotSubscription;
      _roomSnapshotSubscription = null;
      if (previous != null) unawaited(previous.cancel());
      StreamSubscription<AuthorityPublicRoomSnapshot>? subscription;
      var terminated = false;

      bool isCurrent() => _isCurrentRoomWatch(roomId, generation);

      void cancelCurrentWatch() {
        final current = subscription;
        if (identical(_roomSnapshotSubscription, current)) {
          _roomSnapshotSubscription = null;
        }
        if (current != null) unawaited(current.cancel());
      }

      void terminate() {
        if (terminated || !isCurrent()) return;
        terminated = true;
        cancelCurrentWatch();
        _resetRoomWatch(roomId, generation);
      }

      void acceptError(Object error, StackTrace stackTrace) {
        if (terminated || !isCurrent()) return;
        if (error case ClientAuthorityContractViolation(:final code)) {
          _snapshotContractErrorCode = code;
          _addRoomSnapshotError(error, stackTrace: stackTrace);
        } else {
          final code =
              _terminalTransportErrorCode(error) ?? 'roomSnapshotUnavailable';
          _roomSnapshotTransportErrorCode = code;
          _addRoomSnapshotError(
            error is AuthorityTransportException
                ? error
                : AuthorityTransportException(code),
            stackTrace: stackTrace,
          );
        }
        terminate();
      }

      subscription = _snapshots
          .watchRoom(roomId)
          .listen(
            (snapshot) {
              if (terminated || !isCurrent()) return;
              if (_snapshotContractErrorCode != null) {
                terminate();
                return;
              }
              try {
                _applyRoomSnapshot(snapshot);
              } on ClientAuthorityContractViolation catch (error) {
                _snapshotContractErrorCode = error.code;
                _addRoomSnapshotError(error);
                terminate();
              }
            },
            onError: acceptError,
            onDone: () {
              if (terminated || !isCurrent()) return;
              const error = AuthorityTransportException(
                'roomSnapshotStreamEnded',
              );
              _roomSnapshotTransportErrorCode = error.code;
              _addRoomSnapshotError(error);
              terminate();
            },
          );
      _roomSnapshotSubscription = subscription;
      if (terminated) {
        if (identical(_roomSnapshotSubscription, subscription)) {
          _roomSnapshotSubscription = null;
        }
        unawaited(subscription.cancel());
      }
    } on ClientAuthorityContractViolation catch (error) {
      if (roomIdForReset != null && generationForReset != null) {
        _resetRoomWatch(roomIdForReset, generationForReset);
      }
      if (error.code == 'confirmedRoomUnavailable') return;
      _snapshotContractErrorCode = error.code;
      _addRoomSnapshotError(error);
    } on Object {
      if (roomIdForReset != null && generationForReset != null) {
        _resetRoomWatch(roomIdForReset, generationForReset);
      }
      const error = AuthorityTransportException('roomSnapshotUnavailable');
      _roomSnapshotTransportErrorCode = error.code;
      _addRoomSnapshotError(error);
    }
  }

  void _applyRoomSnapshot(
    AuthorityPublicRoomSnapshot snapshot, {
    bool watchGame = true,
    bool restartGameOnSameVersion = false,
  }) {
    final current = _confirmedRoomSnapshot;
    _context.restorePublicRoomSnapshot(snapshot);
    if (current != null && snapshot.roomVersion <= current.roomVersion) {
      if (snapshot.roomVersion < current.roomVersion) return;
      _roomSnapshotTransportErrorCode = null;
      if (snapshot.roomVersion == current.roomVersion &&
          restartGameOnSameVersion &&
          watchGame &&
          snapshot.gameId != null) {
        _watchConfirmedGame();
      }
      return;
    }

    _roomSnapshotTransportErrorCode = null;

    final previousGameId = current?.gameId;
    _confirmedRoomSnapshot = snapshot;
    if (!_roomSnapshotEvents.isClosed) _roomSnapshotEvents.add(snapshot);
    if (snapshot.gameId case final gameId?) {
      if (watchGame) _watchConfirmedGame();
      if (previousGameId != gameId) {
        unawaited(_saveConfirmedLocator().then<void>((_) {}));
      }
    }
  }

  void _applyGameSnapshot(AuthorityPublicSnapshot snapshot) {
    final current = _confirmedGameSnapshot;
    _context.replacePublicSnapshot(snapshot);
    if (current != null && snapshot.stateVersion < current.stateVersion) {
      return;
    }
    _gameSnapshotTransportErrorCode = null;
    if (current != null && snapshot.stateVersion == current.stateVersion) {
      return;
    }
    _confirmedGameSnapshot = snapshot;
    if (!_gameSnapshotEvents.isClosed) _gameSnapshotEvents.add(snapshot);
  }

  void _watchConfirmedGame() {
    String? gameIdForReset;
    int? generationForReset;
    try {
      final gameId = _context.gameId;
      if (_watchedGameId == gameId) return;
      _watchedGameId = gameId;
      final generation = ++_gameWatchGeneration;
      gameIdForReset = gameId;
      generationForReset = generation;
      _session.watch(
        gameId,
        onTerminated: (error) =>
            _acceptGameWatchTermination(gameId, generation, error),
      );
    } on ClientAuthorityContractViolation catch (error) {
      if (gameIdForReset != null && generationForReset != null) {
        _resetGameWatch(gameIdForReset, generationForReset);
      }
      if (error.code == 'confirmedGameUnavailable') return;
      _snapshotContractErrorCode = error.code;
      _addGameSnapshotError(error);
    } on Object {
      if (gameIdForReset != null && generationForReset != null) {
        _resetGameWatch(gameIdForReset, generationForReset);
      }
      const error = AuthorityTransportException('gameSnapshotUnavailable');
      _gameSnapshotTransportErrorCode = error.code;
      _addGameSnapshotError(error);
    }
  }

  void _acceptGameWatchTermination(
    String gameId,
    int generation,
    Object? error,
  ) {
    if (!_isCurrentGameWatch(gameId, generation)) return;
    final transportErrorCode = error == null
        ? null
        : _terminalTransportErrorCode(error);
    if (error case ClientAuthorityContractViolation(:final code)) {
      _snapshotContractErrorCode = code;
      _addGameSnapshotError(error);
    } else if (transportErrorCode != null) {
      _gameSnapshotTransportErrorCode = transportErrorCode;
      _addGameSnapshotError(error!);
    } else if (error == null) {
      const streamEnded = AuthorityTransportException(
        'gameSnapshotStreamEnded',
      );
      _gameSnapshotTransportErrorCode = streamEnded.code;
      _addGameSnapshotError(streamEnded);
    } else {
      const unavailable = AuthorityTransportException(
        'gameSnapshotUnavailable',
      );
      _gameSnapshotTransportErrorCode = unavailable.code;
      _addGameSnapshotError(unavailable);
    }
    _resetGameWatch(gameId, generation);
  }

  bool _isCurrentRoomWatch(String roomId, int generation) =>
      _watchedRoomId == roomId && _roomWatchGeneration == generation;

  bool _isCurrentGameWatch(String gameId, int generation) =>
      _watchedGameId == gameId && _gameWatchGeneration == generation;

  void _resetRoomWatch(String roomId, int generation) {
    if (_isCurrentRoomWatch(roomId, generation)) _watchedRoomId = null;
  }

  void _resetGameWatch(String gameId, int generation) {
    if (_isCurrentGameWatch(gameId, generation)) _watchedGameId = null;
  }

  String? _terminalTransportErrorCode(Object error) =>
      error is AuthorityTransportException &&
          error.code != 'authorityUnavailable'
      ? error.code
      : null;

  void _addRoomSnapshotError(Object error, {StackTrace? stackTrace}) {
    if (!_roomSnapshotEvents.isClosed) {
      _roomSnapshotEvents.addError(error, stackTrace);
    }
  }

  void _addGameSnapshotError(Object error, {StackTrace? stackTrace}) {
    if (!_gameSnapshotEvents.isClosed) {
      _gameSnapshotEvents.addError(error, stackTrace);
    }
  }

  Future<bool> _saveConfirmedLocator() async {
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
      _persistenceErrorCode = null;
      return true;
    } on ClientAuthorityContractViolation catch (error) {
      _persistenceErrorCode = error.code;
      return false;
    } on Object {
      _persistenceErrorCode = 'sessionLocatorStoreUnavailable';
      return false;
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
  required Duration snapshotReadTimeout,
  void Function({bool force})? closeTransport,
}) {
  if (presetId.isEmpty || presetId.trim() != presetId) {
    throw const ClientAuthorityContractViolation('invalidPresetId');
  }
  if (snapshotReadTimeout <= Duration.zero) {
    throw ArgumentError.value(
      snapshotReadTimeout,
      'snapshotReadTimeout',
      'must be positive',
    );
  }
  final wireClient = WireAuthorityClient(transport);
  final session = AuthorityClientSession(
    gateway: wireClient,
    snapshots: wireClient,
    pendingStore: pendingStore,
    deferAcceptedPendingClear: true,
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
      roomSnapshotReadTimeout: snapshotReadTimeout,
    ),
    closeTransport,
    snapshotReadTimeout,
  );
}
