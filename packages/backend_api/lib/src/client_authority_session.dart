import 'dart:async';

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

  Future<AuthorityCommandReply?> send(AuthorityCommandRequest request) async {
    final existing = await _pendingStore.load();
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

    await _pendingStore.save(request);
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
    final pending = await _pendingStore.load();
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
