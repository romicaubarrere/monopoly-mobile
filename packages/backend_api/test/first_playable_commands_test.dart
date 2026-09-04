import 'package:board_backend_api/backend_api.dart';
import 'package:test/test.dart';

void main() {
  test('room commands use canonical family, versions and payloads', () {
    final commands = _commands();

    final create = commands.createRoom(
      presetDraft: const <String, Object?>{'presetId': 'synthetic-vp0'},
    );
    final join = commands.joinRoom(roomCode: 'ABC123');
    final ready = commands.setReady(
      roomId: 'room-1',
      expectedRoomVersion: 4,
      ready: true,
    );
    final start = commands.startGame(roomId: 'room-1', expectedRoomVersion: 5);

    expect(create.family, AuthorityCommandFamily.room);
    expect(create.command['type'], 'CreateRoom');
    expect(create.command['expectedRoomVersion'], isNull);
    expect(create.command['payload'], <String, Object?>{
      'presetDraft': <String, Object?>{'presetId': 'synthetic-vp0'},
    });
    expect(join.command['type'], 'JoinRoom');
    expect(join.command['payload'], <String, Object?>{'roomCode': 'ABC123'});
    expect(ready.command['type'], 'SetReady');
    expect(ready.command['expectedRoomVersion'], 4);
    expect(ready.command['payload'], <String, Object?>{
      'ready': true,
      'roomId': 'room-1',
    });
    expect(start.command['type'], 'StartGame');
    expect(start.command['expectedRoomVersion'], 5);
    expect(start.command['payload'], <String, Object?>{'roomId': 'room-1'});
  });

  test('game commands carry only confirmed target material', () {
    final commands = _commands();

    final roll = commands.rollDice(
      gameId: 'game-1',
      expectedStateVersion: 7,
      actorPlayerId: 'player-1',
    );
    final buy = commands.buyProperty(
      gameId: 'game-1',
      expectedStateVersion: 8,
      actorPlayerId: 'player-1',
      decisionId: 'decision-1',
      propertyId: 'property-7',
    );
    final decline = commands.declineProperty(
      gameId: 'game-1',
      expectedStateVersion: 8,
      actorPlayerId: 'player-1',
      decisionId: 'decision-1',
      propertyId: 'property-7',
    );
    final bid = commands.placeBid(
      gameId: 'game-1',
      expectedStateVersion: 9,
      actorPlayerId: 'player-1',
      auctionId: 'auction-1',
      amount: 120,
    );
    final pass = commands.passAuction(
      gameId: 'game-1',
      expectedStateVersion: 10,
      actorPlayerId: 'player-1',
      auctionId: 'auction-1',
    );

    expect(roll.family, AuthorityCommandFamily.game);
    expect(roll.command['type'], 'RollDice');
    expect(roll.command['expectedStateVersion'], 7);
    expect(roll.command['payload'], isEmpty);
    expect(buy.command['type'], 'BuyProperty');
    expect(buy.command['payload'], <String, Object?>{
      'decisionId': 'decision-1',
      'propertyId': 'property-7',
    });
    expect(decline.command['type'], 'DeclineProperty');
    expect(bid.command['type'], 'PlaceBid');
    expect(bid.command['payload'], <String, Object?>{
      'amount': 120,
      'auctionId': 'auction-1',
    });
    expect(pass.command['type'], 'PassAuction');
    expect(pass.command['payload'], <String, Object?>{
      'auctionId': 'auction-1',
    });
  });

  test('every new intent receives a distinct command identity', () {
    final commands = _commands();
    final first = commands.rollDice(
      gameId: 'game-1',
      expectedStateVersion: 1,
      actorPlayerId: 'player-1',
    );
    final second = commands.rollDice(
      gameId: 'game-1',
      expectedStateVersion: 1,
      actorPlayerId: 'player-1',
    );

    expect(first.commandId, isNot(second.commandId));
    expect(first.inputHash, second.inputHash);
  });

  test('invalid bid and generated identity fail before transport', () {
    final commands = _commands();
    expect(
      () => commands.placeBid(
        gameId: 'game-1',
        expectedStateVersion: 1,
        actorPlayerId: 'player-1',
        auctionId: 'auction-1',
        amount: 0,
      ),
      throwsA(
        isA<ClientAuthorityContractViolation>().having(
          (error) => error.code,
          'code',
          'invalidBidAmount',
        ),
      ),
    );
    expect(
      () =>
          FirstPlayableAuthorityCommands(
            clientInstanceId: 'client-1',
            commandIds: _EmptyCommandIds(),
          ).rollDice(
            gameId: 'game-1',
            expectedStateVersion: 1,
            actorPlayerId: 'player-1',
          ),
      throwsA(
        isA<ClientAuthorityContractViolation>().having(
          (error) => error.code,
          'code',
          'invalidGeneratedCommandId',
        ),
      ),
    );
  });
}

FirstPlayableAuthorityCommands _commands() => FirstPlayableAuthorityCommands(
  clientInstanceId: 'client-1',
  commandIds: _SequentialCommandIds(),
);

final class _SequentialCommandIds implements AuthorityCommandIdSource {
  int _next = 0;

  @override
  String nextCommandId() => 'command-${++_next}';
}

final class _EmptyCommandIds implements AuthorityCommandIdSource {
  @override
  String nextCommandId() => '';
}
