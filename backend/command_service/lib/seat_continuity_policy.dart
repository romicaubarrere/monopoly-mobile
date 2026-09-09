import 'package:board_game_core/game_core.dart';

final class SeatContinuityViolation implements Exception {
  const SeatContinuityViolation(this.code);
  final String code;
  @override
  String toString() => 'SeatContinuityViolation: $code';
}

/// Authority-observed grace metadata, frozen once for one disconnect episode.
/// It is not a new public GameState field or a client-supplied timestamp. A
/// retry/reconnect evaluation reuses this object instead of starting a timer.
final class ReconnectGraceWindow {
  ReconnectGraceWindow({
    required this.playerId,
    required DateTime disconnectedAt,
    required ResolvedPresetConfig frozenPreset,
  }) : disconnectedAt = disconnectedAt.toUtc(),
       deadlineAt = disconnectedAt.toUtc().add(
         Duration(seconds: frozenPreset.reconnectGraceSeconds),
       ) {
    if (playerId.isEmpty) {
      throw const SeatContinuityViolation('invalidPlayerId');
    }
  }

  final String playerId;
  final DateTime disconnectedAt;
  final DateTime deadlineAt;
}

enum SeatContinuityPhase {
  humanActive,
  humanGrace,
  absentNonblocking,
  waitingStableBoundary,
  temporaryBotActive,
  reclaimPending,
  permanentBot,
  inactive,
}

/// A pure policy proposal, not a committed snapshot or an executable bot action.
/// Authority must revalidate membership, version, presence and stable boundary
/// in its atomic state transition before publishing any proposed controller.
final class SeatContinuityDecision {
  const SeatContinuityDecision({
    required this.phase,
    required this.controllerAfter,
  });
  final SeatContinuityPhase phase;
  final SeatControllerState controllerAfter;
}

/// DEC-060 continuity policy, separate from gameplay and bot strategy.
///
/// All booleans are trusted Authority facts, never HTTP/body/UI inputs. This
/// semantic boundary does not detect connectivity, schedule work, increment
/// versions, persist state, execute a command, or access private RNG. In
/// particular an auction/trade timeout alone is not a disconnect observation.
abstract final class SeatContinuityPolicy {
  static SeatContinuityDecision evaluate({
    required PlayerState player,
    required SeatControllerState controller,
    required DateTime authorityNow,
    required bool humanConnected,
    required bool seatBlocksGame,
    required bool atStableBoundary,
    ReconnectGraceWindow? grace,
  }) {
    if (controller.playerId != player.playerId ||
        grace != null && grace.playerId != player.playerId) {
      throw const SeatContinuityViolation('seatIdentityMismatch');
    }
    SeatContinuityDecision unchanged(SeatContinuityPhase phase) =>
        SeatContinuityDecision(phase: phase, controllerAfter: controller);
    if (player.status != PlayerStatus.active) {
      return unchanged(SeatContinuityPhase.inactive);
    }
    if (player.kind == PlayerKind.bot) {
      if (controller.controller != SeatController.bot ||
          controller.takeoverReason != null ||
          controller.humanReclaimPending) {
        throw const SeatContinuityViolation('invalidPermanentBotController');
      }
      return unchanged(SeatContinuityPhase.permanentBot);
    }
    final temporaryBot = controller.controller == SeatController.bot;
    if (temporaryBot &&
        (controller.botPolicyId != 'balanced' ||
            controller.takeoverReason == null)) {
      throw const SeatContinuityViolation('invalidTemporaryBotController');
    }
    if (humanConnected) {
      if (!temporaryBot) return unchanged(SeatContinuityPhase.humanActive);
      if (!atStableBoundary) {
        return SeatContinuityDecision(
          phase: SeatContinuityPhase.reclaimPending,
          controllerAfter: controller.humanReclaimPending
              ? controller
              : SeatControllerState(
                  playerId: player.playerId,
                  controller: SeatController.bot,
                  botPolicyId: controller.botPolicyId,
                  takeoverReason: controller.takeoverReason,
                  takeoverStartedAt: controller.takeoverStartedAt,
                  humanReclaimPending: true,
                ),
        );
      }
      return SeatContinuityDecision(
        phase: SeatContinuityPhase.humanActive,
        controllerAfter: SeatControllerState(
          playerId: player.playerId,
          controller: SeatController.human,
          humanReclaimPending: false,
        ),
      );
    }
    if (temporaryBot) return unchanged(SeatContinuityPhase.temporaryBotActive);
    if (grace == null) {
      throw const SeatContinuityViolation('confirmedGraceRequired');
    }
    final now = authorityNow.toUtc();
    if (now.isBefore(grace.disconnectedAt)) {
      throw const SeatContinuityViolation('disconnectObservationInFuture');
    }
    if (now.isBefore(grace.deadlineAt)) {
      return unchanged(SeatContinuityPhase.humanGrace);
    }
    if (!seatBlocksGame) {
      return unchanged(SeatContinuityPhase.absentNonblocking);
    }
    if (!atStableBoundary) {
      return unchanged(SeatContinuityPhase.waitingStableBoundary);
    }
    return SeatContinuityDecision(
      phase: SeatContinuityPhase.temporaryBotActive,
      controllerAfter: SeatControllerState(
        playerId: player.playerId,
        controller: SeatController.bot,
        botPolicyId: 'balanced',
        takeoverReason: TakeoverReason.disconnectTimeout,
        takeoverStartedAt: now,
        humanReclaimPending: false,
      ),
    );
  }
}
