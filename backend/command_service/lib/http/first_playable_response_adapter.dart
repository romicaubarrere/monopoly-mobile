import 'package:board_backend_api/backend_api.dart' as api;

import '../reconnect_planner.dart' as planner;

/// Maps the durable reconnect planner to the exact public contract consumed by
/// Flutter.
///
/// The planner remains persistence-facing and owns reconciliation semantics.
/// This adapter only translates its already-decided outcome; it never derives
/// versions, command identities, or gameplay results from client input.
abstract final class FirstPlayableResponseAdapter {
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
