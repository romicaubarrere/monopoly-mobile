import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  group('GameCommand', () {
    test('serializes to a byte-stable integer-only golden', () {
      final command = GameCommand(
        commandId: 'cmd-1',
        schemaVersion: 1,
        expectedStateVersion: 7,
        clientInstanceId: 'client-1',
        gameId: 'game-1',
        actorPlayerId: 'p1',
        type: GameCommandType.placeBid,
        payload: <String, Object?>{
          'z': 2,
          'nested': <String, Object?>{'b': true, 'a': 1},
          'a': <Object?>['auction-1', 300],
        },
        sentAt: DateTime.parse('2026-08-24T22:00:00-03:00'),
      );

      expect(
        command.toCanonicalJson(),
        '{"actorPlayerId":"p1","clientInstanceId":"client-1","commandId":"cmd-1","expectedStateVersion":7,"gameId":"game-1","payload":{"a":["auction-1",300],"nested":{"a":1,"b":true},"z":2},"schemaVersion":1,"sentAt":"2026-08-25T01:00:00.000Z","type":"PlaceBid"}',
      );
    });

    test('canonical JSON ignores map insertion order', () {
      final first = CanonicalDomainJson.encode(<String, Object?>{
        'b': 2,
        'a': <String, Object?>{'d': 4, 'c': 3},
      });
      final second = CanonicalDomainJson.encode(<String, Object?>{
        'a': <String, Object?>{'c': 3, 'd': 4},
        'b': 2,
      });

      expect(first, second);
      expect(first, '{"a":{"c":3,"d":4},"b":2}');
    });

    test('rejects floating point and deeply freezes payload', () {
      expect(
        () => GameCommand(
          commandId: 'cmd-1',
          schemaVersion: 1,
          expectedStateVersion: 0,
          clientInstanceId: 'client-1',
          gameId: 'game-1',
          actorPlayerId: 'p1',
          type: GameCommandType.rollDice,
          payload: <String, Object?>{'amount': 1.5},
        ),
        throwsA(isA<DomainContractViolation>()),
      );

      final source = <String, Object?>{
        'items': <Object?>[1, 2],
      };
      final command = GameCommand(
        commandId: 'cmd-2',
        schemaVersion: 1,
        expectedStateVersion: 0,
        clientInstanceId: 'client-1',
        gameId: 'game-1',
        actorPlayerId: 'p1',
        type: GameCommandType.rollDice,
        payload: source,
      );
      (source['items']! as List<Object?>).add(3);

      expect(command.payload['items'], <Object?>[1, 2]);
      expect(
        () => (command.payload['items']! as List<Object?>).add(4),
        throwsUnsupportedError,
      );
    });
  });

  group('GameCommandResult', () {
    test('accepted increments once and produces a stable golden', () {
      final result = GameCommandResult(
        commandId: 'cmd-1',
        status: GameCommandStatus.accepted,
        stateVersionBefore: 7,
        stateVersionAfter: 8,
        events: <GameDomainEvent>[
          GameDomainEvent(type: 'bidPlaced', data: {'amount': 300}),
        ],
        snapshotHash: 'snapshot-8',
        serverProcessedAt: DateTime.parse('2026-08-25T01:00:01Z'),
      );

      expect(
        result.toCanonicalJson(),
        '{"commandId":"cmd-1","events":[{"data":{"amount":300},"type":"bidPlaced"}],"serverProcessedAt":"2026-08-25T01:00:01.000Z","snapshotHash":"snapshot-8","stateVersionAfter":8,"stateVersionBefore":7,"status":"accepted"}',
      );
    });

    test('rejected is zero-mutation and requires a safe error code', () {
      expect(
        () => GameCommandResult(
          commandId: 'cmd-1',
          status: GameCommandStatus.rejected,
          stateVersionBefore: 7,
          stateVersionAfter: 8,
          events: const [],
          errorCode: 'staleVersion',
          serverProcessedAt: DateTime.now(),
        ),
        throwsA(isA<DomainContractViolation>()),
      );
      expect(
        () => GameCommandResult(
          commandId: 'cmd-1',
          status: GameCommandStatus.rejected,
          stateVersionBefore: 7,
          stateVersionAfter: 7,
          events: const [],
          serverProcessedAt: DateTime.now(),
        ),
        throwsA(isA<DomainContractViolation>()),
      );
    });
  });

  group('stable entity invariants', () {
    test('PlayerState rejects negative cash and transient third doubles', () {
      expect(() => _player(cash: -1), throwsA(isA<DomainContractViolation>()));
      expect(
        () => _player(consecutiveDoubles: 3),
        throwsA(isA<DomainContractViolation>()),
      );
      expect(
        () => _player(inCucha: false, cuchaAttempts: 1),
        throwsA(isA<DomainContractViolation>()),
      );
    });

    test('PlayerState freezes unique ownership and keep-card IDs', () {
      final properties = <String>['prop-1'];
      final player = _player(ownedPropertyIds: properties);
      properties.add('prop-2');

      expect(player.ownedPropertyIds, <String>['prop-1']);
      expect(
        () => _player(ownedPropertyIds: <String>['prop-1', 'prop-1']),
        throwsA(isA<DomainContractViolation>()),
      );
    });

    test('PropertyState rejects impossible stable combinations', () {
      expect(
        () => PropertyState(
          propertyId: 'utility-1',
          kind: PropertyKind.utility,
          ownerPlayerId: 'p1',
          mortgaged: false,
          improvementLevel: 1,
        ),
        throwsA(isA<DomainContractViolation>()),
      );
      expect(
        () => PropertyState(
          propertyId: 'street-1',
          kind: PropertyKind.street,
          ownerPlayerId: 'p1',
          mortgaged: true,
          improvementLevel: 2,
        ),
        throwsA(isA<DomainContractViolation>()),
      );
      expect(
        () => PropertyState(
          propertyId: 'street-1',
          kind: PropertyKind.street,
          mortgaged: true,
          improvementLevel: 0,
        ),
        throwsA(isA<DomainContractViolation>()),
      );
    });

    test('temporary controller state cannot contaminate player identity', () {
      final player = _player(kind: PlayerKind.human);
      final controller = SeatControllerState(
        playerId: player.playerId,
        controller: SeatController.bot,
        botPolicyId: 'balanced',
        takeoverReason: TakeoverReason.disconnectTimeout,
        takeoverStartedAt: DateTime.parse('2026-08-25T01:00:00Z'),
        humanReclaimPending: true,
      );

      expect(player.kind, PlayerKind.human);
      expect(controller.controller, SeatController.bot);
      expect(
        () => SeatControllerState(
          playerId: 'p1',
          controller: SeatController.human,
          botPolicyId: 'balanced',
          humanReclaimPending: false,
        ),
        throwsA(isA<DomainContractViolation>()),
      );
    });

    test(
      'GameStateHeader freezes version identities and public commitment',
      () {
        final header = GameStateHeader(
          schemaVersion: 1,
          stateVersion: 0,
          rulesVersion: 'synthetic-rules-v1',
          rngVersion: canonicalRngVersion,
          rngCommitment: 'a' * 64,
          gameId: 'game-1',
          roomId: 'room-1',
          status: GameStatus.active,
        );

        expect(header.toJson()['rngVersion'], canonicalRngVersion);
        expect(
          () => GameStateHeader(
            schemaVersion: 1,
            stateVersion: 0,
            rulesVersion: 'synthetic-rules-v1',
            rngVersion: 'other',
            rngCommitment: 'a' * 64,
            gameId: 'game-1',
            roomId: 'room-1',
            status: GameStatus.active,
          ),
          throwsA(isA<DomainContractViolation>()),
        );
      },
    );

    test('PublicGameState is canonical, immutable, and public-only', () {
      final preset = <String, Object?>{
        'presetId': 'synthetic',
        'startingValue': 1500,
      };
      final state = PublicGameState(
        header: _header(),
        presetConfig: preset,
        roundState: const {'round': 1},
        turnState: const {'currentPlayerId': 'p1'},
        players: <PlayerState>[_player()],
        seatControllers: <SeatControllerState>[
          SeatControllerState(
            playerId: 'p1',
            controller: SeatController.human,
            humanReclaimPending: false,
          ),
        ],
        board: const {'boardVersion': 'synthetic-v1'},
        ownership: const <String, Object?>{},
        bank: const {'cash': 10000},
        freeParkingPot: 0,
        deckPublicState: const {'cardsADiscardCount': 0},
        lastMutation: const {'commandId': 'start-game'},
      );
      preset['startingValue'] = 1;

      expect(state.presetConfig['startingValue'], 1500);
      expect(
        state.toCanonicalJson(),
        contains(
          '"rngCommitment":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"',
        ),
      );
      expect(state.toCanonicalJson(), isNot(contains('seed')));
      expect(state.toCanonicalJson(), isNot(contains('streamCounters')));
    });

    test('PublicGameState fails closed on structural contradictions', () {
      expect(
        () => _publicState(
          players: <PlayerState>[_player(), _player()],
          controllers: const [],
        ),
        throwsA(isA<DomainContractViolation>()),
      );
      expect(
        () => _publicState(controllers: const []),
        throwsA(isA<DomainContractViolation>()),
      );
      expect(
        () => _publicState(freeParkingPot: -1),
        throwsA(isA<DomainContractViolation>()),
      );
      expect(
        () => _publicState(header: _header(status: GameStatus.finished)),
        throwsA(isA<DomainContractViolation>()),
      );
    });
  });
}

GameStateHeader _header({GameStatus status = GameStatus.active}) =>
    GameStateHeader(
      schemaVersion: 1,
      stateVersion: 0,
      rulesVersion: 'synthetic-rules-v1',
      rngVersion: canonicalRngVersion,
      rngCommitment: 'a' * 64,
      gameId: 'game-1',
      roomId: 'room-1',
      status: status,
    );

PublicGameState _publicState({
  GameStateHeader? header,
  List<PlayerState>? players,
  List<SeatControllerState>? controllers,
  int freeParkingPot = 0,
}) => PublicGameState(
  header: header ?? _header(),
  presetConfig: const {'presetId': 'synthetic'},
  roundState: const {'round': 1},
  turnState: const {'currentPlayerId': 'p1'},
  players: players ?? <PlayerState>[_player()],
  seatControllers:
      controllers ??
      <SeatControllerState>[
        SeatControllerState(
          playerId: 'p1',
          controller: SeatController.human,
          humanReclaimPending: false,
        ),
      ],
  board: const {'boardVersion': 'synthetic-v1'},
  ownership: const <String, Object?>{},
  bank: const {'cash': 10000},
  freeParkingPot: freeParkingPot,
  deckPublicState: const {'cardsADiscardCount': 0},
  lastMutation: const {'commandId': 'start-game'},
);

PlayerState _player({
  PlayerKind kind = PlayerKind.human,
  int cash = 1500,
  List<String> ownedPropertyIds = const [],
  bool inCucha = false,
  int cuchaAttempts = 0,
  int consecutiveDoubles = 0,
}) => PlayerState(
  playerId: 'p1',
  seat: 0,
  kind: kind,
  status: PlayerStatus.active,
  cash: cash,
  position: 0,
  ownedPropertyIds: ownedPropertyIds,
  keepCardIds: const [],
  inCucha: inCucha,
  cuchaAttempts: cuchaAttempts,
  consecutiveDoubles: consecutiveDoubles,
  connectivityStatus: ConnectivityStatus.online,
);
