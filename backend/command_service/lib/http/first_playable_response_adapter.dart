import 'package:board_backend_api/backend_api.dart' as api;

import '../buy_auction_planner.dart';
import '../reconnect_planner.dart' as planner;
import '../roll_movement_planner.dart';

/// Maps the durable reconnect planner to the exact public contract consumed by
/// Flutter.
///
/// The planner remains persistence-facing and owns reconciliation semantics.
/// This adapter only translates its already-decided outcome; it never derives
/// versions, command identities, or gameplay results from client input.
abstract final class FirstPlayableResponseAdapter {
  static api.AuthorityCommandReply rollMovement(
    AuthorityRollMovementEvaluation evaluation,
  ) => switch (evaluation) {
    AuthorityRollMovementAccepted(:final plan) => api.AuthorityCommandReply(
      commandId: plan.enginePlan.commandId,
      status: api.AuthorityCommandStatus.accepted,
      versionBefore: plan.enginePlan.stateVersionBefore,
      versionAfter: plan.enginePlan.stateVersionAfter,
      publicResult: plan.safeResultSummary,
      snapshot: api.AuthorityPublicSnapshot(plan.stateAfter.toJson()),
    ),
    AuthorityRollMovementRejected(:final rejection) =>
      api.AuthorityCommandReply(
        commandId: rejection.commandId,
        status: api.AuthorityCommandStatus.rejected,
        versionBefore: rejection.stateVersionBefore,
        versionAfter: rejection.stateVersionAfter,
        errorCode: rejection.errorCode.wireValue,
        publicResult: rejection.toPublicJson(),
      ),
  };

  static api.AuthorityCommandReply buyAuction(
    AuthorityBuyAuctionEvaluation evaluation,
  ) => switch (evaluation) {
    AuthorityBuyAuctionAccepted(:final plan) => api.AuthorityCommandReply(
      commandId: plan.enginePlan.commandId,
      status: api.AuthorityCommandStatus.accepted,
      versionBefore: plan.enginePlan.stateVersionBefore,
      versionAfter: plan.enginePlan.stateVersionAfter,
      publicResult: plan.safeResultSummary,
      snapshot: api.AuthorityPublicSnapshot(plan.stateAfter.toJson()),
    ),
    AuthorityBuyAuctionRejected(:final rejection) => api.AuthorityCommandReply(
      commandId: rejection.commandId,
      status: api.AuthorityCommandStatus.rejected,
      versionBefore: rejection.stateVersionBefore,
      versionAfter: rejection.stateVersionAfter,
      errorCode: rejection.errorCode.wireValue,
      publicResult: rejection.toPublicJson(),
    ),
    AuthorityBuyAuctionNoOp(:final reason) =>
      throw AuthorityBuyAuctionViolation('nonCommandEvaluation:$reason'),
  };

  /// Replays a persisted command result without re-invoking Engine or RNG.
  ///
  /// Historical receipts need not retain a full snapshot: Flutter converges
  /// through the public snapshot stream/reconnect when Authority has advanced
  /// beyond this command's [versionAfter].
  static api.AuthorityCommandReply duplicate(
    planner.DurableCommandReceipt receipt,
  ) {
    final result = receipt.publicResult;
    final commandId = result['commandId'];
    final versionBefore = result['stateVersionBefore'];
    final versionAfter = result['stateVersionAfter'];
    if (commandId != receipt.commandId ||
        versionBefore is! int ||
        versionAfter is! int) {
      throw const planner.AuthorityReconnectViolation(
        'invalidDurableCommandResult',
      );
    }
    final originalStatus = result['status'];
    final errorCode = result['errorCode'];
    if ((originalStatus != 'accepted' && originalStatus != 'rejected') ||
        originalStatus == 'rejected' &&
            (errorCode is! String || errorCode.isEmpty)) {
      throw const planner.AuthorityReconnectViolation(
        'invalidDurableCommandResult',
      );
    }
    return api.AuthorityCommandReply(
      commandId: receipt.commandId,
      status: api.AuthorityCommandStatus.duplicate,
      versionBefore: versionBefore,
      versionAfter: versionAfter,
      errorCode: errorCode as String?,
      publicResult: result,
    );
  }

  static api.AuthorityReconnectReply reconnect({
    required planner.AuthorityReconnectPlan plan,
    required api.AuthorityReconnectRequest request,
  }) {
    final identity = request.uncertainCommand;
    final disposition = switch (plan.disposition) {
      planner.ReconnectDisposition.upToDate =>
        api.ReconnectDisposition.upToDate,
      planner.ReconnectDisposition.snapshotAdvanced =>
        api.ReconnectDisposition.snapshotAdvanced,
      planner.ReconnectDisposition.uncertainConfirmed =>
        api.ReconnectDisposition.uncertainConfirmed,
      planner.ReconnectDisposition.uncertainRejected =>
        api.ReconnectDisposition.uncertainRejected,
      planner.ReconnectDisposition.retrySameCommand =>
        api.ReconnectDisposition.retrySameCommand,
      planner.ReconnectDisposition.semanticCollision =>
        api.ReconnectDisposition.semanticCollision,
    };
    final action = switch (plan.disposition) {
      planner.ReconnectDisposition.upToDate ||
      planner.ReconnectDisposition.snapshotAdvanced => null,
      planner.ReconnectDisposition.uncertainConfirmed ||
      planner.ReconnectDisposition.uncertainRejected =>
        api.CommandResolutionAction.useDurableResult,
      planner.ReconnectDisposition.retrySameCommand =>
        api.CommandResolutionAction.retrySameCommand,
      planner.ReconnectDisposition.semanticCollision =>
        api.CommandResolutionAction.failClosed,
    };
    if ((action == null) != (identity == null)) {
      throw const planner.AuthorityReconnectViolation(
        'reconnectIdentityMismatch',
      );
    }

    final resolution = action == null
        ? null
        : api.ReconnectCommandResolution(
            identity: identity!,
            action: action,
            publicResult: action == api.CommandResolutionAction.useDurableResult
                ? _durablePublicResult(plan)
                : null,
            errorCode: action == api.CommandResolutionAction.failClosed
                ? _safeErrorCode(plan)
                : null,
          );
    return api.AuthorityReconnectReply(
      disposition: disposition,
      snapshot: api.AuthorityPublicSnapshot(plan.authoritativeState.toJson()),
      commandResolution: resolution,
    );
  }

  static Map<String, Object?> _durablePublicResult(
    planner.AuthorityReconnectPlan plan,
  ) {
    final result = plan.commandResolution?['result'];
    if (result is! Map<String, Object?>) {
      throw const planner.AuthorityReconnectViolation(
        'missingDurablePublicResult',
      );
    }
    return result;
  }

  static String _safeErrorCode(planner.AuthorityReconnectPlan plan) {
    final errorCode = plan.commandResolution?['errorCode'];
    if (errorCode is! String || errorCode.isEmpty) {
      throw const planner.AuthorityReconnectViolation(
        'missingReconnectErrorCode',
      );
    }
    return errorCode;
  }
}
