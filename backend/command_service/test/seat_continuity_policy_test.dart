import 'package:board_command_service/command_service.dart';
import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

import 'support/synthetic_roll_fixture.dart';

void main() {
  final state = syntheticRollState();
  final player = state.players.first;
  final human = state.seatControllers.first;
  final disconnectedAt = DateTime.utc(2026, 9, 7, 12);
  final preset = syntheticRollCatalog().resolvePreset('express', 2);
  final grace = ReconnectGraceWindow(
    playerId: player.playerId,
    disconnectedAt: disconnectedAt,
    frozenPreset: preset,
  );

  SeatContinuityDecision evaluate({
    SeatControllerState? controller,
    DateTime? now,
    bool connected = false,
    bool blocking = true,
    bool stable = true,
  }) => SeatContinuityPolicy.evaluate(
    player: player,
    controller: controller ?? human,
    grace: grace,
    authorityNow: now ?? grace.deadlineAt,
    humanConnected: connected,
    seatBlocksGame: blocking,
    atStableBoundary: stable,
  );

  test('grace freezes the selected preset duration and normalizes UTC', () {
    expect(grace.disconnectedAt, disconnectedAt);
    expect(
      grace.deadlineAt.difference(disconnectedAt).inSeconds,
      preset.reconnectGraceSeconds,
    );
    final sameInstant = ReconnectGraceWindow(
      playerId: player.playerId,
      disconnectedAt: DateTime.parse('2026-09-07T09:00:00-03:00'),
      frozenPreset: preset,
    );
    expect(sameInstant.deadlineAt, grace.deadlineAt);
    expect(sameInstant.deadlineAt.isUtc, isTrue);
  });

  test(
    'before grace expiry there is no new controller, even when blocking',
    () {
      final decision = evaluate(
        now: grace.deadlineAt.subtract(const Duration(microseconds: 1)),
      );
      expect(decision.phase, SeatContinuityPhase.humanGrace);
      expect(decision.controllerAfter, same(human));
    },
  );

  for (final offset in [Duration.zero, const Duration(seconds: 1)]) {
    test(
      'at/after grace $offset only a blocking stable seat gets takeover',
      () {
        final now = grace.deadlineAt.add(offset);
        final before = state.toCanonicalJson();
        final decision = evaluate(now: now);
        expect(decision.phase, SeatContinuityPhase.temporaryBotActive);
        expect(decision.controllerAfter.controller, SeatController.bot);
        expect(decision.controllerAfter.botPolicyId, 'balanced');
        expect(decision.controllerAfter.playerId, player.playerId);
        expect(
          decision.controllerAfter.takeoverReason,
          TakeoverReason.disconnectTimeout,
        );
        expect(decision.controllerAfter.takeoverStartedAt, now);
        expect(decision.controllerAfter.humanReclaimPending, isFalse);
        expect(state.toCanonicalJson(), before);
        expect(player.kind, PlayerKind.human);
        expect(player.status, PlayerStatus.active);
      },
    );
  }

  test('expired nonblocking absence never fabricates takeover or forfeit', () {
    final decision = evaluate(blocking: false);
    expect(decision.phase, SeatContinuityPhase.absentNonblocking);
    expect(decision.controllerAfter, same(human));
  });

  test('an atomic transition is never interrupted by a controller switch', () {
    final decision = evaluate(stable: false);
    expect(decision.phase, SeatContinuityPhase.waitingStableBoundary);
    expect(decision.controllerAfter, same(human));
  });

  test(
    'repeat takeover evaluation preserves start time and controller identity',
    () {
      final active = evaluate().controllerAfter;
      final repeat = evaluate(
        controller: active,
        now: grace.deadlineAt.add(const Duration(minutes: 1)),
      );
      expect(repeat.phase, SeatContinuityPhase.temporaryBotActive);
      expect(repeat.controllerAfter, same(active));
      expect(
        grace.deadlineAt.difference(disconnectedAt).inSeconds,
        preset.reconnectGraceSeconds,
      );
    },
  );

  test('return during an atomic action requests reclaim without changing controller', () {
    final active = evaluate().controllerAfter;
    final pending = evaluate(
      controller: active,
      connected: true,
      stable: false,
    );
    expect(pending.phase, SeatContinuityPhase.reclaimPending);
    expect(pending.controllerAfter.controller, SeatController.bot);
    expect(pending.controllerAfter.takeoverStartedAt, active.takeoverStartedAt);
    expect(pending.controllerAfter.humanReclaimPending, isTrue);
    final repeat = evaluate(
      controller: pending.controllerAfter,
      connected: true,
      stable: false,
    );
    expect(repeat.controllerAfter, same(pending.controllerAfter));
  });

  test(
    'stable-boundary reclaim removes all temporary state, without replay',
    () {
      final active = evaluate().controllerAfter;
      final pending = evaluate(
        controller: active,
        connected: true,
        stable: false,
      );
      final reclaimed = evaluate(
        controller: pending.controllerAfter,
        connected: true,
      );
      expect(reclaimed.phase, SeatContinuityPhase.humanActive);
      expect(reclaimed.controllerAfter.toJson(), human.toJson());
      final repeat = evaluate(
        controller: reclaimed.controllerAfter,
        connected: true,
      );
      expect(repeat.controllerAfter, same(reclaimed.controllerAfter));
    },
  );

  test(
    'a remembered reclaim intent does not reclaim while the human is absent',
    () {
      final pending = evaluate(
        controller: evaluate().controllerAfter,
        connected: true,
        stable: false,
      );
      final absent = evaluate(
        controller: pending.controllerAfter,
        connected: false,
      );
      expect(absent.phase, SeatContinuityPhase.temporaryBotActive);
      expect(absent.controllerAfter.controller, SeatController.bot);
    },
  );

  test(
    'reconnect before grace keeps human control and never extends deadline',
    () {
      final deadline = grace.deadlineAt;
      final decision = evaluate(connected: true, now: disconnectedAt);
      expect(decision.phase, SeatContinuityPhase.humanActive);
      expect(decision.controllerAfter, same(human));
      expect(grace.deadlineAt, deadline);
    },
  );

  test('missing confirmed grace fails closed, not an implicit timeout', () {
    expect(
      () => SeatContinuityPolicy.evaluate(
        player: player,
        controller: human,
        authorityNow: grace.deadlineAt,
        humanConnected: false,
        seatBlocksGame: true,
        atStableBoundary: true,
      ),
      throwsA(
        isA<SeatContinuityViolation>().having(
          (e) => e.code,
          'code',
          'confirmedGraceRequired',
        ),
      ),
    );
  });

  test('future disconnect observation fails closed', () {
    expect(
      () => evaluate(now: disconnectedAt.subtract(const Duration(seconds: 1))),
      throwsA(
        isA<SeatContinuityViolation>().having(
          (e) => e.code,
          'code',
          'disconnectObservationInFuture',
        ),
      ),
    );
  });

  test('foreign grace and controller identities fail closed', () {
    for (final foreignGrace in [true, false]) {
      expect(
        () => SeatContinuityPolicy.evaluate(
          player: player,
          controller: foreignGrace ? human : state.seatControllers.last,
          grace: foreignGrace
              ? ReconnectGraceWindow(
                  playerId: 'p2',
                  disconnectedAt: disconnectedAt,
                  frozenPreset: preset,
                )
              : grace,
          authorityNow: grace.deadlineAt,
          humanConnected: false,
          seatBlocksGame: true,
          atStableBoundary: true,
        ),
        throwsA(
          isA<SeatContinuityViolation>().having(
            (e) => e.code,
            'code',
            'seatIdentityMismatch',
          ),
        ),
      );
    }
  });

  test('permanent bots cannot be reclaimed as human seats', () {
    final botPlayer = _playerLike(player, kind: PlayerKind.bot);
    final bot = SeatControllerState(
      playerId: player.playerId,
      controller: SeatController.bot,
      botPolicyId: 'balanced',
      humanReclaimPending: false,
    );
    final decision = SeatContinuityPolicy.evaluate(
      player: botPlayer,
      controller: bot,
      authorityNow: grace.deadlineAt,
      humanConnected: true,
      seatBlocksGame: true,
      atStableBoundary: true,
    );
    expect(decision.phase, SeatContinuityPhase.permanentBot);
    expect(decision.controllerAfter, same(bot));
  });

  for (final status in [PlayerStatus.bankrupt, PlayerStatus.finished]) {
    test('$status never reactivates a controller', () {
      final decision = SeatContinuityPolicy.evaluate(
        player: _playerLike(player, status: status),
        controller: human,
        grace: grace,
        authorityNow: grace.deadlineAt,
        humanConnected: false,
        seatBlocksGame: true,
        atStableBoundary: true,
      );
      expect(decision.phase, SeatContinuityPhase.inactive);
      expect(decision.controllerAfter, same(human));
    });
  }

  test('noncanonical temporary controller fails closed', () {
    for (final policy in ['balanced', 'unrecognized']) {
      final controller = SeatControllerState(
        playerId: player.playerId,
        controller: SeatController.bot,
        botPolicyId: policy,
        humanReclaimPending: false,
        takeoverReason: policy == 'balanced'
            ? null
            : TakeoverReason.disconnectTimeout,
        takeoverStartedAt: policy == 'balanced' ? null : disconnectedAt,
      );
      expect(
        () => evaluate(controller: controller),
        throwsA(isA<SeatContinuityViolation>()),
      );
    }
  });
}

PlayerState _playerLike(
  PlayerState player, {
  PlayerKind? kind,
  PlayerStatus? status,
}) => PlayerState(
  playerId: player.playerId,
  seat: player.seat,
  kind: kind ?? player.kind,
  status: status ?? player.status,
  cash: player.cash,
  position: player.position,
  ownedPropertyIds: player.ownedPropertyIds,
  keepCardIds: player.keepCardIds,
  inCucha: player.inCucha,
  cuchaAttempts: player.cuchaAttempts,
  consecutiveDoubles: player.consecutiveDoubles,
  connectivityStatus: player.connectivityStatus,
);
