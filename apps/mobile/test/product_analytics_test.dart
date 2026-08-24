import 'package:board_mobile/analytics/product_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const platform = AnalyticsPlatform.test;
  const appVersion = '0.1.0+1';

  ProductAnalyticsEvent action({
    OperationResult result = OperationResult.success,
  }) =>
      ProductAnalyticsEvent.gameAction(
        eventId: 'logical-command-1',
        occurredAtMs: 123,
        appVersion: appVersion,
        platform: platform,
        confirmedPreset: 'express_b',
        confirmedRulesVersion: 'rules-v1',
        actionType: GameActionType.roll,
        result: result,
        durationMs: 400,
      );

  test('canonical event-name allowlist contains exactly ten names', () {
    expect(ProductEventName.values, hasLength(10));
    expect(
      ProductEventName.values.map((event) => event.wireName).toSet(),
      <String>{
        'room_create_result',
        'room_join_result',
        'game_start_result',
        'turn_completed',
        'game_action',
        'pending_decision_shown',
        'reconnect_result',
        'game_finished',
        'balance_outcome',
        'playtest_rating',
      },
    );
  });

  test('event shape cannot carry forbidden identity or private-state fields', () {
    final event = action();
    final keys = event.parameters.keys.toSet();

    expect(keys, isNot(contains('uid')));
    expect(keys, isNot(contains('player_id')));
    expect(keys, isNot(contains('room_code')));
    expect(keys, isNot(contains('auth_token')));
    expect(keys, isNot(contains('rng_seed')));
    expect(keys, isNot(contains('future_deck_order')));
    expect(keys, isNot(contains('free_text')));
    expect(keys, isNot(contains('command_payload')));
  });

  test('successful start requires confirmed preset and rules version', () {
    expect(
      () => ProductAnalyticsEvent.gameStartResult(
        eventId: 'start-1',
        occurredAtMs: 1,
        appVersion: appVersion,
        platform: platform,
        result: OperationResult.success,
        latencyMs: 100,
      ),
      throwsArgumentError,
    );
  });

  test('same confirmed retry emits at most one logical success event', () async {
    final sink = RecordingAnalyticsSink();
    final analytics = ProductAnalytics(sink);

    await analytics.emit(action());
    await analytics.emit(action());

    expect(sink.events, hasLength(1));
    expect(sink.events.single.name, 'game_action');
    expect(sink.events.single.parameters['result'], 'success');
  });

  test('unknown lost-ack can later reconcile to one success', () async {
    final sink = RecordingAnalyticsSink();
    final analytics = ProductAnalytics(sink);

    await analytics.emit(action(result: OperationResult.unknown));
    await analytics.emit(action(result: OperationResult.success));
    await analytics.emit(action(result: OperationResult.success));

    expect(sink.events, hasLength(2));
    expect(
      sink.events.map((event) => event.parameters['result']),
      <Object?>['unknown', 'success'],
    );
  });

  test('sink exception is fail-open and permits a later retry', () async {
    final sink = RecordingAnalyticsSink()..errorToThrow = StateError('sdk');
    final analytics = ProductAnalytics(sink);

    await expectLater(analytics.emit(action()), completes);
    expect(sink.events, isEmpty);

    sink.errorToThrow = null;
    await analytics.emit(action());
    expect(sink.events, hasLength(1));
  });

  test('playtest rating rejects values outside the closed 1-5 range', () {
    expect(
      () => ProductAnalyticsEvent.playtestRating(
        eventId: 'rating-1',
        occurredAtMs: 1,
        appVersion: appVersion,
        platform: platform,
        fairness: 6,
        agency: 4,
        fun: 4,
        pace: 4,
        preferredVariant: 'express_b',
      ),
      throwsRangeError,
    );
  });

  test('noop sink is safe for disabled analytics', () async {
    final analytics = ProductAnalytics(const NoopAnalyticsSink());
    await expectLater(analytics.emit(action()), completes);
  });
}
