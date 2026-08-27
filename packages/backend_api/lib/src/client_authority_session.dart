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
  }) : this._(gateway, snapshots, pendingStore);

  AuthorityClientSession._(this._gateway, this._snapshots, this._pendingStore);

  final CommandGateway _gateway;
  final AuthoritySnapshotRepository _snapshots;
  final PendingAuthorityCommandStore _pendingStore;
  final StreamController<AuthoritySessionState> _states =
      StreamController<AuthoritySessionState>.broadcast(sync: true);
  AuthoritySessionState _state = const AuthoritySessionState();
  StreamSubscription<AuthorityPublicSnapshot>? _snapshotSubscription;

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
        case CommandResolutionAction.useDurableResult:
          if (pending != null) await _pendingStore.clear(pending.commandId);
          _publish(
            AuthoritySessionState(
              status: AuthoritySessionStatus.confirmed,
              snapshot: reply.snapshot,
            ),
          );
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

  void watch(String gameId) {
    _snapshotSubscription?.cancel();
    _snapshotSubscription = _snapshots
        .watchGame(gameId)
        .listen(
          (snapshot) {
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
          onError: (_) {
            _publish(
              AuthoritySessionState(
                status: AuthoritySessionStatus.uncertain,
                snapshot: _state.snapshot,
                pendingCommand: _state.pendingCommand,
                safeErrorCode: 'snapshotStreamUnavailable',
              ),
            );
          },
        );
  }

  Future<void> close() async {
    await _snapshotSubscription?.cancel();
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
      await _pendingStore.clear(request.commandId);
      final rejected = reply.status == AuthorityCommandStatus.rejected;
      _publish(
        AuthoritySessionState(
          status: rejected
              ? AuthoritySessionStatus.rejected
              : AuthoritySessionStatus.confirmed,
          snapshot: reply.snapshot ?? _state.snapshot,
          reply: reply,
          safeErrorCode: reply.errorCode,
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
