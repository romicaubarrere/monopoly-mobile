import 'package:board_game_core/game_core.dart';

/// Membership does not grant simultaneous control of a bot-controlled seat.
/// Call only after authenticating membership, inside the transaction's current
/// state evaluation. Duplicate receipts must be resolved before this check.
abstract final class HumanControllerGate {
  static bool rejects(PublicGameState state, String playerId) {
    final players = state.players.where(
      (player) => player.playerId == playerId,
    );
    // Preserve Engine's existing actorNotInGame / inactive-player validation.
    if (players.isEmpty || players.single.status != PlayerStatus.active) {
      return false;
    }
    if (players.single.kind != PlayerKind.human) return true;
    final controllers = state.seatControllers.where(
      (controller) => controller.playerId == playerId,
    );
    return controllers.length != 1 ||
        controllers.single.controller != SeatController.human;
  }
}
