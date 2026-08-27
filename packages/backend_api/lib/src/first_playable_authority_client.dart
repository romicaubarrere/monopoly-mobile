import 'dart:async';
import 'dart:io';

import 'client_authority.dart';
import 'client_authority_adapter.dart';
import 'client_authority_session.dart';
import 'first_playable_binding.dart';
import 'first_playable_commands.dart';
import 'first_playable_context.dart';
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
    required AuthorityCommandIdSource commandIds,
    required String clientInstanceId,
    required String presetId,
  }) => _compose(
    transport: transport,
    pendingStore: pendingStore,
    commandIds: commandIds,
    clientInstanceId: clientInstanceId,
    presetId: presetId,
  );

  factory FirstPlayableAuthorityClient.http({
    required Uri baseUri,
    required AuthorityIdTokenProvider idTokenProvider,
    required PendingAuthorityCommandStore pendingStore,
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
      commandIds: commandIds,
      clientInstanceId: clientInstanceId,
      presetId: presetId,
      closeTransport: transport.close,
    );
  }

  FirstPlayableAuthorityClient._(
    this._session,
    this._context,
    this._binding,
    this._closeTransport,
  ) {
    _stateSubscription = _session.states.listen(_acceptSessionState);
  }

  final AuthorityClientSession _session;
  final FirstPlayableAuthorityContext _context;
  final SessionFirstPlayableAuthorityBinding _binding;
  final void Function({bool force})? _closeTransport;
  late final StreamSubscription<AuthoritySessionState> _stateSubscription;
  String? _watchedGameId;
  String? _snapshotContractErrorCode;

  AuthoritySessionState get state => _session.state;
  Stream<AuthoritySessionState> get states => _session.states;

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
    return result;
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
}

FirstPlayableAuthorityClient _compose({
  required AuthorityWireTransport transport,
  required PendingAuthorityCommandStore pendingStore,
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
    SessionFirstPlayableAuthorityBinding(
      session: session,
      requests: requests,
      roomSnapshots: wireClient,
    ),
    closeTransport,
  );
}
