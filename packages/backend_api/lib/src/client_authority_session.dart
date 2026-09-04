import 'dart:async';
import 'dart:convert';

import 'client_authority.dart';

enum AuthoritySessionStatus {
  idle,
  sending,
  confirmed,
  rejected,
  uncertain,
  reconnecting,
  blocked,
}

/// Client-owned receipt storage. A mobile implementation must persist this
/// before the network call so process death cannot mint a replacement command.
abstract interface class PendingAuthorityCommandStore {
  Future<void> save(AuthorityCommandRequest request);

  Future<AuthorityCommandRequest?> load();

  Future<void> clear(String commandId);
}

typedef PendingAuthorityCommandJsonRead = Future<String?> Function();
typedef PendingAuthorityCommandJsonWrite = Future<void> Function(String? value);

/// Canonical durable adapter for the one uncertain mobile command.
///
/// Flutter supplies only atomic key-value read/write callbacks (for example a
/// device persistence plugin). This adapter owns wire serialization and strict
/// decoding so the app does not maintain a second command schema. Corrupt,
/// non-canonical or mismatched data fails closed instead of minting a new
/// command identity after process death.
final class JsonPendingAuthorityCommandStore
    implements PendingAuthorityCommandStore {
  JsonPendingAuthorityCommandStore({
    required PendingAuthorityCommandJsonRead read,
    required PendingAuthorityCommandJsonWrite write,
  }) : this._(read, write);

  const JsonPendingAuthorityCommandStore._(this._read, this._write);

  static const int _maximumStoredBytes = 64 * 1024;

  final PendingAuthorityCommandJsonRead _read;
  final PendingAuthorityCommandJsonWrite _write;

  @override
  Future<void> save(AuthorityCommandRequest request) =>
      _write(request.toCanonicalWireJson());

  @override
  Future<AuthorityCommandRequest?> load() async {
    final value = await _read();
    if (value == null) return null;
    if (value.isEmpty || utf8.encode(value).length > _maximumStoredBytes) {
      throw const ClientAuthorityContractViolation('pendingCommandCorrupt');
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        throw const ClientAuthorityContractViolation('pendingCommandCorrupt');
      }
      final request = AuthorityCommandRequest.fromWireJson(decoded);
      if (request.toCanonicalWireJson() != value) {
        throw const ClientAuthorityContractViolation('pendingCommandCorrupt');
      }
      return request;
    } on ClientAuthorityContractViolation {
      throw const ClientAuthorityContractViolation('pendingCommandCorrupt');
    } on FormatException {
      throw const ClientAuthorityContractViolation('pendingCommandCorrupt');
    }
  }

  @override
  Future<void> clear(String commandId) async {
    final existing = await load();
    if (existing == null) return;
    if (existing.commandId != commandId) {
      throw const ClientAuthorityContractViolation(
        'pendingCommandClearMismatch',
      );
    }
    await _write(null);
  }
}

final class AuthoritySessionState {
  const AuthoritySessionState({
    this.status = AuthoritySessionStatus.idle,
    this.snapshot,
    this.reply,
    this.pendingCommand,
    this.safeErrorCode,
  });

  final AuthoritySessionStatus status;
  final AuthorityPublicSnapshot? snapshot;
  final AuthorityCommandReply? reply;
  final AuthorityCommandRequest? pendingCommand;
  final String? safeErrorCode;
}

/// Exact durable command retried after a transport outcome was uncertain.
///
/// The request is loaded from [PendingAuthorityCommandStore] rather than
/// reconstructed by presentation. Callers can therefore apply the matching
/// Authority reply to their confirmed context without minting a new identity.
final class AuthorityPendingCommandRetry {
  const AuthorityPendingCommandRetry({
    required this.request,
    required this.reply,
  });

  final AuthorityCommandRequest request;
  final AuthorityCommandReply? reply;
}

/// Coordinates confirmed Authority state without interpreting gameplay rules.
///
/// Commands are durably marked uncertain before transport. Only Authority
/// replies or replacement snapshots update confirmed state. Transport failure
/// keeps the exact request for reconnect/retry.
final class AuthorityClientSession {
  AuthorityClientSession({
    required CommandGateway gateway,
    required AuthoritySnapshotRepository snapshots,
    required PendingAuthorityCommandStore pendingStore,
    bool deferAcceptedPendingClear = false,
  }) : this._(
         gateway,
         snapshots,
         pendingStore,
         deferAcceptedPendingClear,
       );

  AuthorityClientSession._(
    this._gateway,
    this._snapshots,
    this._pendingStore,
    this._deferAcceptedPendingClear,
  );

  final CommandGateway _gateway;
  final AuthoritySnapshotRepository _snapshots;
  final PendingAuthorityCommandStore _pendingStore;
  final bool _deferAcceptedPendingClear;
  final StreamController<AuthoritySessionState> _states =
      StreamController<AuthoritySessionState>.broadcast(sync: true);
  AuthoritySessionState _state = const AuthoritySessionState();
  StreamSubscription<AuthorityPublicSnapshot>? _snapshotSubscription;
  int _snapshotWatchGeneration = 0;

  AuthoritySessionState get state => _state;
  Stream<AuthoritySessionState> get states => _states.stream;

  /// Restores a snapshot already authenticated and validated by the wire port.
  void restorePublicSnapshot(AuthorityPublicSnapshot snapshot) {
    final current = _state.snapshot;
    if (current != null && snapshot.stateVersion < current.stateVersion) return;
    _publish(
      AuthoritySessionState(
        status: AuthoritySessionStatus.confirmed,
        snapshot: snapshot,
        pendingCommand: _state.pendingCommand,
      ),
    );
  }

  Future<AuthorityCommandReply?> send(AuthorityCommandRequest request) async {
    late final AuthorityCommandRequest? existing;
    try {
      existing = await _pendingStore.load();
    } on ClientAuthorityContractViolation catch (error) {
      _publishPendingStoreBlocked(error.code);
      return null;
    } on Object {
      _publishPendingStoreBlocked('pendingCommandStoreUnavailable');
      return null;
    }
    if (existing != null &&
        (existing.commandId != request.commandId ||
            existing.inputHash != request.inputHash)) {
      _publish(
        AuthoritySessionState(
          status: AuthoritySessionStatus.blocked,
          snapshot: _state.snapshot,
          pendingCommand: existing,
          safeErrorCode: 'uncertainCommandPending',
        ),
      );
      return null;
    }

    try {
      await _pendingStore.save(request);
    } on ClientAuthorityContractViolation catch (error) {
      _publishPendingStoreBlocked(error.code);
      return null;
    } on Object {
      _publishPendingStoreBlocked('pendingCommandStoreUnavailable');
      return null;
    }
    _publish(
      AuthoritySessionState(
        status: AuthoritySessionStatus.sending,
        snapshot: _state.snapshot,
        pendingCommand: request,
      ),
    );
    return _sendSaved(request);
  }

  /// Restores a persisted uncertain command without sending it.
  ///
  /// Process restart must not silently discard a command identity that was
  /// saved before its ACK was lost. Presentation can inspect the resulting
  /// state and explicitly ask Authority to reconcile or replay that exact
  /// identity.
  Future<AuthorityCommandRequest?> restorePendingCommand() async {
    try {
      final pending = await _pendingStore.load();
      if (pending == null) return null;
      _publish(
        AuthoritySessionState(
          status: AuthoritySessionStatus.uncertain,
          snapshot: _state.snapshot,
          pendingCommand: pending,
          safeErrorCode: 'pendingCommandRecoveryRequired',
        ),
      );
      return pending;
    } on ClientAuthorityContractViolation catch (error) {
      _publishPendingStoreBlocked(error.code);
      rethrow;
    } on Object {
      const error = ClientAuthorityContractViolation(
        'pendingCommandStoreUnavailable',
      );
      _publishPendingStoreBlocked(error.code);
      throw error;
    }
  }

  /// Finalizes an accepted command after the caller durably persisted the
  /// public locator derived from its Authority reply.
  ///
  /// This optional two-phase acknowledgement closes the crash window between a
  /// received Create/Join ACK and storing the public room locator. Rejections
  /// are already safe to clear immediately because they cannot create state.
  Future<bool> acknowledgeConfirmedPendingCommand() async {
    if (!_deferAcceptedPendingClear) return true;
    final current = _state;
    final pending = current.pendingCommand;
    if (pending == null) return true;
    if (current.status != AuthoritySessionStatus.confirmed) return false;
    try {
      await _pendingStore.clear(pending.commandId);
      // A public game replacement can arrive while durable storage is
      // clearing. Preserve the latest replacement rather than publishing the
      // snapshot captured before the await and rolling the session backward.
      final latest = _state;
      final latestPending = latest.pendingCommand;
      if (latestPending == null) return true;
      if (latestPending.commandId != pending.commandId) {
        _publish(
          AuthoritySessionState(
            status: AuthoritySessionStatus.blocked,
            snapshot: latest.snapshot,
            pendingCommand: latestPending,
            safeErrorCode: 'pendingCommandStoreMismatch',
          ),
        );
        return false;
      }
      _publish(
        AuthoritySessionState(
          status: latest.status,
          snapshot: latest.snapshot,
          reply: latest.reply,
          safeErrorCode: latest.safeErrorCode,
        ),
      );
      return true;
    } on ClientAuthorityContractViolation catch (error) {
      _publishPendingStoreBlocked(error.code);
      return false;
    } on Object {
      _publishPendingStoreBlocked('pendingCommandStoreUnavailable');
      return false;
    }
  }

  Future<AuthorityReconnectReply?> reconnect(String gameId) async {
    late final AuthorityCommandRequest? pending;
    try {
      pending = await _pendingStore.load();
    } on ClientAuthorityContractViolation catch (error) {
      _publishPendingStoreBlocked(error.code);
      return null;
    } on Object {
      _publishPendingStoreBlocked('pendingCommandStoreUnavailable');
      return null;
    }
    final snapshot = _state.snapshot;
    _publish(
      AuthoritySessionState(
        status: AuthoritySessionStatus.reconnecting,
        snapshot: snapshot,
        pendingCommand: pending,
      ),
    );

    try {
      final reply = await _snapshots.reconnect(
        AuthorityReconnectRequest(
          gameId: gameId,
          observedStateVersion: snapshot?.stateVersion ?? 0,
          uncertainCommand: pending?.uncertainIdentity,
        ),
      );
      final resolution = reply.commandResolution;
      switch (resolution?.action) {
        case CommandResolutionAction.useDurableResult: {
          final durableRejected =
              reply.disposition == ReconnectDisposition.uncertainRejected ||
              resolution?.publicResult?['status'] == 'rejected';
          final retainPending =
              _deferAcceptedPendingClear && !durableRejected;
          if (pending != null && !retainPending) {
            await _pendingStore.clear(pending.commandId);
          }
          _publish(
            AuthoritySessionState(
              status: AuthoritySessionStatus.confirmed,
              snapshot: reply.snapshot,
              pendingCommand: retainPending ? pending : null,
            ),
          );
        }
        case CommandResolutionAction.retrySameCommand:
          if (pending == null) {
            _publish(
              AuthoritySessionState(
                status: AuthoritySessionStatus.blocked,
                snapshot: reply.snapshot,
                safeErrorCode: 'missingUncertainCommand',
              ),
            );
          } else {
            _publish(
              AuthoritySessionState(
                status: AuthoritySessionStatus.sending,
                snapshot: reply.snapshot,
                pendingCommand: pending,
              ),
            );
            await _sendSaved(pending);
          }
        case CommandResolutionAction.failClosed:
          _publish(
            AuthoritySessionState(
              status: AuthoritySessionStatus.blocked,
              snapshot: reply.snapshot,
              pendingCommand: pending,
              safeErrorCode: resolution?.errorCode ?? 'semanticCollision',
            ),
          );
        case null:
          _publish(
            AuthoritySessionState(
              status: AuthoritySessionStatus.confirmed,
              snapshot: reply.snapshot,
              pendingCommand: pending,
            ),
          );
      }
      return reply;
    } on ClientAuthorityContractViolation catch (error) {
      _publish(
        AuthoritySessionState(
          status: AuthoritySessionStatus.blocked,
          snapshot: snapshot,
          pendingCommand: pending,
          safeErrorCode: error.code,
        ),
      );
      return null;
    } on Object {
      _publish(
        AuthoritySessionState(
          status: AuthoritySessionStatus.uncertain,
          snapshot: snapshot,
          pendingCommand: pending,
          safeErrorCode: 'reconnectUnavailable',
        ),
      );
      return null;
    }
  }

  /// Replays the one durable uncertain command without requiring a game.
  ///
  /// This covers room commands such as Create, Join and Ready, whose receipt
  /// has the same idempotency guarantees as game commands but cannot use the
  /// game-scoped reconnect endpoint yet.
  Future<AuthorityPendingCommandRetry?> retryPendingCommand() async {
    final current = _state;
    if (current.status == AuthoritySessionStatus.blocked &&
        current.safeErrorCode != 'uncertainCommandPending' &&
        current.safeErrorCode != 'pendingCommandStoreUnavailable') {
      // A contract/storage failure is intentionally fail-closed. The sole
      // blocked state that remains replayable is the guard emitted when a
      // second presentation command was attempted while the first one was
      // already durable and uncertain.
      return null;
    }
    late final AuthorityCommandRequest? pending;
    try {
      pending = await _pendingStore.load();
    } on ClientAuthorityContractViolation catch (error) {
      _publishPendingStoreBlocked(error.code);
      return null;
    } on Object {
      _publishPendingStoreBlocked('pendingCommandStoreUnavailable');
      return null;
    }
    if (pending == null) {
      _publish(
        AuthoritySessionState(
          status: AuthoritySessionStatus.blocked,
          snapshot: _state.snapshot,
          safeErrorCode: 'missingUncertainCommand',
        ),
      );
      return null;
    }
    if (pending.family != AuthorityCommandFamily.room) {
      _publish(
        AuthoritySessionState(
          status: AuthoritySessionStatus.blocked,
          snapshot: _state.snapshot,
          pendingCommand: pending,
          safeErrorCode: 'pendingCommandRequiresGameReconnect',
        ),
      );
      return null;
    }
    _publish(
      AuthoritySessionState(
        status: AuthoritySessionStatus.sending,
        snapshot: _state.snapshot,
        pendingCommand: pending,
      ),
    );
    final reply = await _sendSaved(pending);
    return AuthorityPendingCommandRetry(request: pending, reply: reply);
  }

  void _publishPendingStoreBlocked(String safeErrorCode) {
    _publish(
      AuthoritySessionState(
        status: AuthoritySessionStatus.blocked,
        snapshot: _state.snapshot,
        pendingCommand: _state.pendingCommand,
        safeErrorCode: safeErrorCode,
      ),
    );
  }

  /// Begins replacing the confirmed snapshot from one public game stream.
  ///
  /// A terminal stream error is deliberately distinct from a contract error:
  /// an availability failure leaves the exact command/reconnect path usable,
  /// while a malformed public snapshot fails closed. The optional callback is
  /// invoked once whenever this watch ends so its owner can explicitly start a
  /// fresh watch after refresh or reconnect.
  void watch(String gameId, {void Function(Object? error)? onTerminated}) {
    final generation = ++_snapshotWatchGeneration;
    final previous = _snapshotSubscription;
    _snapshotSubscription = null;
    if (previous != null) unawaited(previous.cancel());
    var terminated = false;
    StreamSubscription<AuthorityPublicSnapshot>? subscription;

    bool isCurrent() => _snapshotWatchGeneration == generation;

    void stopCurrentWatch() {
      if (!isCurrent()) return;
      final current = subscription;
      if (identical(_snapshotSubscription, current)) {
        _snapshotSubscription = null;
      }
      if (current != null) unawaited(current.cancel());
    }

    void notifyTerminated([Object? error]) {
      if (terminated || !isCurrent()) return;
      terminated = true;
      onTerminated?.call(error);
    }

    subscription = _snapshots
        .watchGame(gameId)
        .listen(
          (snapshot) {
            if (terminated || !isCurrent()) return;
            final current = _state.snapshot;
            if (current == null ||
                snapshot.stateVersion >= current.stateVersion) {
              _publish(
                AuthoritySessionState(
                  status: AuthoritySessionStatus.confirmed,
                  snapshot: snapshot,
                  pendingCommand: _state.pendingCommand,
                ),
              );
            }
          },
          onError: (Object error, StackTrace _) {
            if (terminated || !isCurrent()) return;
            if (error case ClientAuthorityContractViolation(:final code)) {
              _publish(
                AuthoritySessionState(
                  status: AuthoritySessionStatus.blocked,
                  snapshot: _state.snapshot,
                  pendingCommand: _state.pendingCommand,
                  safeErrorCode: code,
                ),
              );
            } else {
              _publish(
                AuthoritySessionState(
                  status: AuthoritySessionStatus.uncertain,
                  snapshot: _state.snapshot,
                  pendingCommand: _state.pendingCommand,
                  safeErrorCode: 'snapshotStreamUnavailable',
                ),
              );
            }
            notifyTerminated(error);
            stopCurrentWatch();
          },
          onDone: () {
            if (!isCurrent()) return;
            if (identical(_snapshotSubscription, subscription)) {
              _snapshotSubscription = null;
            }
            notifyTerminated();
          },
        );
    _snapshotSubscription = subscription;
    // A synchronous stream can report an error while [listen] is being set
    // up. Cancel it after assignment as well so no stale data can revive a
    // terminated watch.
    if (terminated) stopCurrentWatch();
  }

  Future<void> close() async {
    _snapshotWatchGeneration += 1;
    await _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    await _states.close();
  }

  Future<AuthorityCommandReply?> _sendSaved(
    AuthorityCommandRequest request,
  ) async {
    try {
      final reply = await _gateway.send(request);
      if (reply.commandId != request.commandId) {
        throw const ClientAuthorityContractViolation('replyCommandMismatch');
      }
      final rejected = reply.isRejectedOutcome;
      final retainPending = _deferAcceptedPendingClear && !rejected;
      if (!retainPending) await _pendingStore.clear(request.commandId);
      _publish(
        AuthoritySessionState(
          status: rejected
              ? AuthoritySessionStatus.rejected
              : AuthoritySessionStatus.confirmed,
          snapshot: reply.snapshot ?? _state.snapshot,
          reply: reply,
          pendingCommand: retainPending ? request : null,
          safeErrorCode: rejected
              ? reply.errorCode ?? 'durableCommandRejected'
              : null,
        ),
      );
      return reply;
    } on ClientAuthorityContractViolation catch (error) {
      _publish(
        AuthoritySessionState(
          status: AuthoritySessionStatus.blocked,
          snapshot: _state.snapshot,
          pendingCommand: request,
          safeErrorCode: error.code,
        ),
      );
      return null;
    } on Object {
      _publish(
        AuthoritySessionState(
          status: AuthoritySessionStatus.uncertain,
          snapshot: _state.snapshot,
          pendingCommand: request,
          safeErrorCode: 'commandOutcomeUncertain',
        ),
      );
      return null;
    }
  }

  void _publish(AuthoritySessionState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
