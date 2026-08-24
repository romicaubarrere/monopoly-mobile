import 'dart:async';

enum AnalyticsPlatform { ios, android, test }

enum ProductEventName {
  roomCreateResult,
  roomJoinResult,
  gameStartResult,
  turnCompleted,
  gameAction,
  pendingDecisionShown,
  reconnectResult,
  gameFinished,
  balanceOutcome,
  playtestRating,
}

enum OperationResult { success, rejected, networkError, unavailable, unknown }

enum GameActionType {
  roll,
  buy,
  declineProperty,
  auctionBid,
  auctionPass,
  tradeOffer,
  tradeAccept,
  tradeReject,
  mortgage,
  unmortgage,
  build,
  debtAction,
  cuchaAction,
  endTurn,
}

enum DecisionType { propertyOffer, auction, trade, debt, cucha, card }

enum FinishReason { completed, roundCap, bankruptcy, abandoned }

extension on Enum {
  String get wireName => name.replaceAllMapped(
    RegExp(r'([A-Z])'),
    (match) => '_${match.group(1)!.toLowerCase()}',
  );
}

extension ProductEventNameWire on ProductEventName {
  String get wireName => switch (this) {
    ProductEventName.roomCreateResult => 'room_create_result',
    ProductEventName.roomJoinResult => 'room_join_result',
    ProductEventName.gameStartResult => 'game_start_result',
    ProductEventName.turnCompleted => 'turn_completed',
    ProductEventName.gameAction => 'game_action',
    ProductEventName.pendingDecisionShown => 'pending_decision_shown',
    ProductEventName.reconnectResult => 'reconnect_result',
    ProductEventName.gameFinished => 'game_finished',
    ProductEventName.balanceOutcome => 'balance_outcome',
    ProductEventName.playtestRating => 'playtest_rating',
  };
}

abstract interface class AnalyticsSink {
  Future<void> send(String eventName, Map<String, Object> parameters);
}

final class NoopAnalyticsSink implements AnalyticsSink {
  const NoopAnalyticsSink();

  @override
  Future<void> send(String eventName, Map<String, Object> parameters) async {}
}

final class RecordingAnalyticsSink implements AnalyticsSink {
  final List<RecordedAnalyticsEvent> events = <RecordedAnalyticsEvent>[];
  Object? errorToThrow;

  @override
  Future<void> send(String eventName, Map<String, Object> parameters) async {
    if (errorToThrow case final Object error) {
      throw error;
    }
    events.add(RecordedAnalyticsEvent(eventName, Map.unmodifiable(parameters)));
  }
}

final class RecordedAnalyticsEvent {
  const RecordedAnalyticsEvent(this.name, this.parameters);

  final String name;
  final Map<String, Object> parameters;
}

final class ProductAnalyticsEvent {
  ProductAnalyticsEvent._({
    required this.name,
    required this.eventId,
    required this.occurredAtMs,
    required this.appVersion,
    required this.platform,
    required Map<String, Object> parameters,
  }) : parameters = Map.unmodifiable(<String, Object>{
         'event_id': eventId,
         'occurred_at_ms': occurredAtMs,
         'app_version': appVersion,
         'platform': platform.wireName,
         ...parameters,
       });

  final ProductEventName name;
  final String eventId;
  final int occurredAtMs;
  final String appVersion;
  final AnalyticsPlatform platform;
  final Map<String, Object> parameters;

  String get dedupeKey {
    final result = parameters['result'] ?? 'event';
    return '${name.wireName}:$eventId:$result';
  }

  static ProductAnalyticsEvent roomCreateResult({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required OperationResult result,
    required int latencyMs,
  }) => _resultEvent(
    name: ProductEventName.roomCreateResult,
    eventId: eventId,
    occurredAtMs: occurredAtMs,
    appVersion: appVersion,
    platform: platform,
    result: result,
    latencyMs: latencyMs,
  );

  static ProductAnalyticsEvent roomJoinResult({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required OperationResult result,
    required int latencyMs,
  }) => _resultEvent(
    name: ProductEventName.roomJoinResult,
    eventId: eventId,
    occurredAtMs: occurredAtMs,
    appVersion: appVersion,
    platform: platform,
    result: result,
    latencyMs: latencyMs,
  );

  static ProductAnalyticsEvent gameStartResult({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required OperationResult result,
    required int latencyMs,
    String? confirmedPreset,
    String? confirmedRulesVersion,
  }) {
    if (result == OperationResult.success &&
        (confirmedPreset == null || confirmedRulesVersion == null)) {
      throw ArgumentError(
        'Successful game_start_result requires confirmed preset and rules version.',
      );
    }
    return ProductAnalyticsEvent._(
      name: ProductEventName.gameStartResult,
      eventId: eventId,
      occurredAtMs: occurredAtMs,
      appVersion: appVersion,
      platform: platform,
      parameters: <String, Object>{
        'result': result.wireName,
        'latency_ms': latencyMs,
        if (confirmedPreset != null) 'preset': confirmedPreset,
        if (confirmedRulesVersion != null)
          'rules_version': confirmedRulesVersion,
      },
    );
  }

  static ProductAnalyticsEvent turnCompleted({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required String confirmedPreset,
    required String confirmedRulesVersion,
    required int round,
    required int turnIndex,
    required int durationMs,
    required int decisionCount,
  }) => ProductAnalyticsEvent._(
    name: ProductEventName.turnCompleted,
    eventId: eventId,
    occurredAtMs: occurredAtMs,
    appVersion: appVersion,
    platform: platform,
    parameters: <String, Object>{
      'preset': confirmedPreset,
      'rules_version': confirmedRulesVersion,
      'round': round,
      'turn_index': turnIndex,
      'duration_ms': durationMs,
      'decision_count': decisionCount,
    },
  );

  static ProductAnalyticsEvent gameAction({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required String confirmedPreset,
    required String confirmedRulesVersion,
    required GameActionType actionType,
    required OperationResult result,
    required int durationMs,
  }) => ProductAnalyticsEvent._(
    name: ProductEventName.gameAction,
    eventId: eventId,
    occurredAtMs: occurredAtMs,
    appVersion: appVersion,
    platform: platform,
    parameters: <String, Object>{
      'action_type': actionType.wireName,
      'result': result.wireName,
      'duration_ms': durationMs,
      'preset': confirmedPreset,
      'rules_version': confirmedRulesVersion,
    },
  );

  static ProductAnalyticsEvent pendingDecisionShown({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required String confirmedPreset,
    required String confirmedRulesVersion,
    required DecisionType decisionType,
  }) => ProductAnalyticsEvent._(
    name: ProductEventName.pendingDecisionShown,
    eventId: eventId,
    occurredAtMs: occurredAtMs,
    appVersion: appVersion,
    platform: platform,
    parameters: <String, Object>{
      'decision_type': decisionType.wireName,
      'preset': confirmedPreset,
      'rules_version': confirmedRulesVersion,
    },
  );

  static ProductAnalyticsEvent reconnectResult({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required OperationResult result,
    required int durationMs,
    required int stateGap,
    String? confirmedRulesVersion,
  }) => ProductAnalyticsEvent._(
    name: ProductEventName.reconnectResult,
    eventId: eventId,
    occurredAtMs: occurredAtMs,
    appVersion: appVersion,
    platform: platform,
    parameters: <String, Object>{
      'result': result.wireName,
      'duration_ms': durationMs,
      'state_gap': stateGap,
      if (confirmedRulesVersion != null) 'rules_version': confirmedRulesVersion,
    },
  );

  static ProductAnalyticsEvent gameFinished({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required String confirmedPreset,
    required String confirmedRulesVersion,
    required int rounds,
    required int durationMs,
    required FinishReason finishReason,
    required int playerCount,
  }) => ProductAnalyticsEvent._(
    name: ProductEventName.gameFinished,
    eventId: eventId,
    occurredAtMs: occurredAtMs,
    appVersion: appVersion,
    platform: platform,
    parameters: <String, Object>{
      'preset': confirmedPreset,
      'rules_version': confirmedRulesVersion,
      'rounds': rounds,
      'duration_ms': durationMs,
      'finish_reason': finishReason.wireName,
      'player_count': playerCount,
    },
  );

  static ProductAnalyticsEvent balanceOutcome({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required String confirmedPreset,
    required String confirmedRulesVersion,
    required int groupsTotal,
    required int buildsTotal,
    required int bankruptcies,
    required String netWorthGapBucket,
  }) => ProductAnalyticsEvent._(
    name: ProductEventName.balanceOutcome,
    eventId: eventId,
    occurredAtMs: occurredAtMs,
    appVersion: appVersion,
    platform: platform,
    parameters: <String, Object>{
      'groups_total': groupsTotal,
      'builds_total': buildsTotal,
      'bankruptcies': bankruptcies,
      'net_worth_gap_bucket': netWorthGapBucket,
      'preset': confirmedPreset,
      'rules_version': confirmedRulesVersion,
    },
  );

  static ProductAnalyticsEvent playtestRating({
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required int fairness,
    required int agency,
    required int fun,
    required int pace,
    required String preferredVariant,
  }) {
    for (final value in <int>[fairness, agency, fun, pace]) {
      if (value < 1 || value > 5) {
        throw RangeError.range(value, 1, 5, 'rating');
      }
    }
    return ProductAnalyticsEvent._(
      name: ProductEventName.playtestRating,
      eventId: eventId,
      occurredAtMs: occurredAtMs,
      appVersion: appVersion,
      platform: platform,
      parameters: <String, Object>{
        'fairness_1_5': fairness,
        'agency_1_5': agency,
        'fun_1_5': fun,
        'pace_1_5': pace,
        'preferred_variant': preferredVariant,
      },
    );
  }

  static ProductAnalyticsEvent _resultEvent({
    required ProductEventName name,
    required String eventId,
    required int occurredAtMs,
    required String appVersion,
    required AnalyticsPlatform platform,
    required OperationResult result,
    required int latencyMs,
  }) => ProductAnalyticsEvent._(
    name: name,
    eventId: eventId,
    occurredAtMs: occurredAtMs,
    appVersion: appVersion,
    platform: platform,
    parameters: <String, Object>{
      'result': result.wireName,
      'latency_ms': latencyMs,
    },
  );
}

final class ProductAnalytics {
  ProductAnalytics(this._sink);

  final AnalyticsSink _sink;
  final Set<String> _emitted = <String>{};

  Future<void> emit(ProductAnalyticsEvent event) async {
    if (!_emitted.add(event.dedupeKey)) {
      return;
    }
    try {
      await _sink.send(event.name.wireName, event.parameters);
    } catch (_) {
      _emitted.remove(event.dedupeKey);
    }
  }
}
