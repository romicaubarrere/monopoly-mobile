import 'package:board_backend_api/backend_api.dart';

/// Narrow presentation port for the live First Playable.
///
/// It exposes only public Authority data that the UI must render. Gameplay
/// legality, membership authorization and persistence remain server-owned.
abstract interface class LiveFirstPlayableAuthority {
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  });

  String? get latestCreatedRoomCode;

  Future<AuthorityPublicRoomSnapshot> refreshLobby();

  /// Most recently validated lobby state, if this device has joined a room.
  AuthorityPublicRoomSnapshot? get confirmedLobbySnapshot;

  /// Most recently validated public game state, if the room has started.
  AuthorityPublicSnapshot? get confirmedGameSnapshot;

  /// Authenticated public room replacement snapshots.
  Stream<AuthorityPublicRoomSnapshot> get lobbySnapshots;

  /// Authenticated public game replacement snapshots.
  Stream<AuthorityPublicSnapshot> get gameSnapshots;

  /// A durable command identity survived a restart and needs explicit
  /// Authority reconciliation before the user can issue another command.
  bool get requiresReconciliation;
}

final class ClientLiveFirstPlayableAuthority
    implements LiveFirstPlayableAuthority {
  const ClientLiveFirstPlayableAuthority(this.client);

  final FirstPlayableAuthorityClient client;

  @override
  String? get latestCreatedRoomCode => client.latestCreatedRoomCode;

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) => client.perform(action, input: input);

  @override
  Future<AuthorityPublicRoomSnapshot> refreshLobby() =>
      client.refreshConfirmedRoom();

  @override
  AuthorityPublicRoomSnapshot? get confirmedLobbySnapshot =>
      client.confirmedRoomSnapshot;

  @override
  AuthorityPublicSnapshot? get confirmedGameSnapshot =>
      client.confirmedGameSnapshot;

  @override
  Stream<AuthorityPublicRoomSnapshot> get lobbySnapshots =>
      client.roomSnapshots;

  @override
  Stream<AuthorityPublicSnapshot> get gameSnapshots => client.gameSnapshots;

  @override
  bool get requiresReconciliation => client.requiresReconciliation;
}
