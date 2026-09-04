import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/first_playable/live_first_playable_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'created room projects Authority snapshots instead of advancing on ACKs',
    (tester) async {
      final authority = _FakeLiveAuthority();
      addTearDown(authority.close);
      await tester.pumpWidget(_app(authority));

      await tester.tap(find.text('Crear partida'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear sala'));
      await tester.pumpAndSettle();

      expect(find.text('CÓDIGO · ABC123'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live-member-player-host')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('live-member-player-guest')),
        findsOneWidget,
      );
      expect(find.text('Romina PLACEHOLDER'), findsNothing);
      expect(find.textContaining('ABC 123'), findsNothing);
      final startButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Empezar partida'),
      );
      expect(startButton.onPressed, isNotNull);
      expect(find.textContaining('Start se habilita cuando'), findsNothing);

      await tester.tap(find.text('Estoy lista'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empezar partida'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('live-game-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-board')), findsNothing);

      authority.emitGame(
        _gameSnapshot(
          version: 0,
          phase: 'awaitingRoll',
          currentPlayerId: 'player-host',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('live-board')), findsOneWidget);
      expect(find.text('PARTIDA · game-live'), findsOneWidget);
      expect(find.text('VERSIÓN · 0'), findsOneWidget);
      expect(find.text('PRESET · express'), findsOneWidget);

      await tester.tap(find.text('Tirar dados'));
      await tester.pumpAndSettle();
      expect(authority.actions.last, FirstPlayableAuthorityAction.roll);
      expect(find.byKey(const ValueKey('live-board')), findsOneWidget);
      expect(find.byKey(const ValueKey('live-property')), findsNothing);

      authority.emitGame(
        _gameSnapshot(
          version: 1,
          phase: 'awaitingPropertyDecision',
          currentPlayerId: 'player-host',
          propertyOffer: true,
          lastRoll: const [2, 3],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('live-property')), findsOneWidget);
      expect(find.text('No comprar · abrir subasta'), findsOneWidget);
      expect(find.text('Dados confirmados: 2 + 3 = 5.'), findsOneWidget);

      await tester.tap(find.text('No comprar · abrir subasta'));
      await tester.pumpAndSettle();
      expect(
        authority.actions.last,
        FirstPlayableAuthorityAction.declineProperty,
      );
      expect(find.byKey(const ValueKey('live-property')), findsOneWidget);

      authority.emitGame(
        _gameSnapshot(
          version: 2,
          phase: 'awaitingAuctionBid',
          currentPlayerId: 'player-host',
          auction: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('live-auction')), findsOneWidget);
      expect(find.text('Pasar'), findsOneWidget);
    },
  );

  testWidgets('guest receives the host-started game from public streams', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority(actorPlayerId: 'player-guest');
    addTearDown(authority.close);
    await tester.pumpWidget(_app(authority));

    authority.emitGame(
      _gameSnapshot(
        version: 0,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-host',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-board')), findsNothing);

    authority.emitLobby(gameId: 'game-live');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('live-board')), findsOneWidget);
    expect(find.text('Esperando turno'), findsOneWidget);
    expect(find.text('Tirar dados'), findsNothing);

    authority.emitGame(
      _gameSnapshot(
        version: 1,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-guest',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tu turno'), findsOneWidget);
    expect(find.text('Tirar dados'), findsOneWidget);
  });

  testWidgets('restored open room renders its confirmed lobby', (tester) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    authority.emitLobby();

    await tester.pumpWidget(_app(authority));

    expect(find.byKey(const ValueKey('live-lobby')), findsOneWidget);
    expect(find.text('SALA CONFIRMADA'), findsOneWidget);
  });

  testWidgets('stale lobby replacement cannot roll UI back', (tester) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    await tester.pumpWidget(_app(authority));

    authority.emitLobby(gameId: 'game-live', roomVersion: 4);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-game-loading')), findsOneWidget);

    authority.emitLobby(roomVersion: 3);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('live-game-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-lobby')), findsNothing);
  });

  testWidgets('stale game replacement cannot roll UI back', (tester) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    await tester.pumpWidget(_app(authority));

    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 2,
        phase: 'awaitingAuctionBid',
        currentPlayerId: 'player-host',
        auction: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-auction')), findsOneWidget);

    authority.emitGame(
      _gameSnapshot(
        version: 1,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-host',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('live-auction')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-board')), findsNothing);
  });

  testWidgets('highest pending game replacement wins before lobby arrives', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    await tester.pumpWidget(_app(authority));

    authority.emitGame(
      _gameSnapshot(
        version: 2,
        phase: 'awaitingAuctionBid',
        currentPlayerId: 'player-host',
        auction: true,
      ),
    );
    authority.emitGame(
      _gameSnapshot(
        version: 1,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-host',
      ),
    );
    authority.emitLobby(gameId: 'game-live');
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('live-auction')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-board')), findsNothing);
  });

  testWidgets('changing Authority clears the previous session snapshots', (
    tester,
  ) async {
    final previous = _FakeLiveAuthority();
    final replacement = _FakeLiveAuthority();
    addTearDown(previous.close);
    addTearDown(replacement.close);
    previous.emitLobby(gameId: 'game-live');
    previous.emitGame(
      _gameSnapshot(
        version: 0,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-host',
      ),
    );

    await tester.pumpWidget(_app(previous));
    expect(find.byKey(const ValueKey('live-board')), findsOneWidget);

    await tester.pumpWidget(_app(replacement));
    await tester.pumpAndSettle();

    expect(find.text('Crear partida'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-board')), findsNothing);
    expect(find.text('PARTIDA · game-live'), findsNothing);
  });

  testWidgets(
    'reconnect returns to the confirmed game when its version is unchanged',
    (tester) async {
      final authority = _FakeLiveAuthority();
      addTearDown(authority.close);
      authority.emitLobby(gameId: 'game-live');
      authority.emitGame(
        _gameSnapshot(
          version: 0,
          phase: 'awaitingRoll',
          currentPlayerId: 'player-host',
        ),
      );
      authority.rollOutcome = FirstPlayableAuthorityOutcome.uncertain;

      await tester.pumpWidget(_app(authority));
      expect(find.byKey(const ValueKey('live-board')), findsOneWidget);

      await tester.tap(find.text('Tirar dados'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-reconnect')), findsOneWidget);

      await tester.tap(find.text('Reconciliar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('live-board')), findsOneWidget);
    },
  );

  testWidgets('restored durable command requires reconciliation before play', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority()..requiresReconciliation = true;
    addTearDown(authority.close);
    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 0,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-host',
      ),
    );

    await tester.pumpWidget(_app(authority));

    expect(find.byKey(const ValueKey('live-reconnect')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-board')), findsNothing);
  });

  testWidgets('recovered Create shows its Authority-issued room code', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority()..requiresReconciliation = true;
    addTearDown(authority.close);
    await tester.pumpWidget(_app(authority));

    await tester.tap(find.text('Reconciliar'));
    await tester.pumpAndSettle();

    expect(authority.actions.single, FirstPlayableAuthorityAction.reconnect);
    expect(find.byKey(const ValueKey('live-lobby')), findsOneWidget);
    expect(find.text('CÓDIGO · ABC123'), findsOneWidget);
  });

  testWidgets(
    'accepted reconciliation remains required when lobby refresh fails',
    (tester) async {
      final authority = _FakeLiveAuthority()
        ..requiresReconciliation = true
        ..failRefresh = true;
      addTearDown(authority.close);
      await tester.pumpWidget(_app(authority));

      await tester.tap(find.text('Reconciliar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('live-reconnect')), findsOneWidget);
      expect(find.text('Authority · roomSnapshotUnavailable'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('live-snapshot-recovery-action')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'durable rejected recovery exits reconnect with its safe result',
    (tester) async {
      final authority = _FakeLiveAuthority()
        ..requiresReconciliation = true
        ..reconnectOutcome = FirstPlayableAuthorityOutcome.rejected;
      addTearDown(authority.close);
      await tester.pumpWidget(_app(authority));

      await tester.tap(find.text('Reconciliar'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('live-reconnect')), findsNothing);
      expect(find.text('Crear partida'), findsOneWidget);
      expect(find.text('Authority · rejected'), findsOneWidget);
    },
  );

  testWidgets('old reconnect continuation cannot clear replacement recovery', (
    tester,
  ) async {
    final previous = _FakeLiveAuthority();
    final replacement = _FakeLiveAuthority()..requiresReconciliation = true;
    final refresh = Completer<AuthorityPublicRoomSnapshot>();
    previous.refreshCompleter = refresh;
    addTearDown(previous.close);
    addTearDown(replacement.close);
    previous.emitLobby(gameId: 'game-live');
    previous.emitGame(
      _gameSnapshot(
        version: 0,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-host',
      ),
    );
    previous.rollOutcome = FirstPlayableAuthorityOutcome.uncertain;

    await tester.pumpWidget(_app(previous));
    await tester.tap(find.text('Tirar dados'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconciliar'));
    await tester.pump();

    await tester.pumpWidget(_app(replacement));
    await tester.pumpAndSettle();
    refresh.complete(previous._lobbySnapshot(gameId: 'game-live'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('live-reconnect')), findsOneWidget);
    expect(find.text('Crear partida'), findsNothing);
  });

  testWidgets('surfaces terminal Authority snapshot errors', (tester) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 0,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-host',
      ),
    );

    await tester.pumpWidget(_app(authority));
    authority.emitGameError(
      const AuthorityTransportException('authenticationRejected'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Authority · authenticationRejected'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-snapshot-recovery-action')),
      findsOneWidget,
    );

    authority.emitLobby(gameId: 'game-live', roomVersion: 5);
    await tester.pumpAndSettle();
    expect(find.text('Authority · authenticationRejected'), findsOneWidget);

    authority.emitGame(
      _gameSnapshot(
        version: 1,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-host',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-safe-error')), findsNothing);
  });

  testWidgets('join keeps entered Authority room code in confirmed lobby', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority(actorPlayerId: 'player-guest');
    addTearDown(authority.close);
    await tester.pumpWidget(_app(authority));

    await tester.tap(find.text('Unirse con código'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('live-room-code-input')),
      'abc123',
    );
    await tester.tap(find.text('Unirse'));
    await tester.pumpAndSettle();

    expect(authority.lastInput, 'ABC123');
    expect(find.text('CÓDIGO · ABC123'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-member-player-host')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('live-member-player-guest')),
      findsOneWidget,
    );
    expect(find.text('Empezar partida'), findsNothing);
  });

  testWidgets('renders a confirmed property purchase outcome receipt', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 2,
        phase: 'turnResolved',
        currentPlayerId: 'player-guest',
        lastMutation: _buyAuctionMutation(
          _outcome('propertyPurchased', <String, Object?>{
            'playerId': 'player-host',
            'propertyId': 'street-07',
            'price': 107,
          }),
        ),
        ownership: const <String, Object?>{
          'byPropertyId': <String, Object?>{'street-07': 'player-host'},
        },
      ),
    );

    await tester.pumpWidget(_app(authority));

    expect(
      find.byKey(const ValueKey('live-confirmed-buy-outcome')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Compra confirmada · street-07 pertenece a player-host. Pago confirmado: 107.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders confirmed terminal auction outcome receipts', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 2,
        phase: 'turnResolved',
        currentPlayerId: 'player-guest',
        lastMutation: _buyAuctionMutation(
          _outcome('auctionWon', <String, Object?>{
            'auctionId': 'auction-07',
            'propertyId': 'street-07',
            'winnerPlayerId': 'player-guest',
            'winningBid': 40,
          }),
        ),
        ownership: const <String, Object?>{
          'byPropertyId': <String, Object?>{'street-07': 'player-guest'},
        },
      ),
    );

    await tester.pumpWidget(_app(authority));

    expect(
      find.byKey(const ValueKey('live-confirmed-auction-award')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Subasta adjudicada · street-07 pertenece a player-guest. Pago confirmado: 40.',
      ),
      findsOneWidget,
    );

    authority.emitGame(
      _gameSnapshot(
        version: 3,
        phase: 'turnResolved',
        currentPlayerId: 'player-host',
        lastMutation: _buyAuctionMutation(
          _outcome('auctionEndedWithoutWinner', <String, Object?>{
            'auctionId': 'auction-08',
            'propertyId': 'street-08',
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('live-confirmed-auction-award')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('live-confirmed-auction-no-winner')),
      findsOneWidget,
    );
    expect(
      find.text('Subasta cerrada · street-08 quedó sin adjudicar.'),
      findsOneWidget,
    );
  });

  testWidgets('keeps buy auction snapshots without an outcome compatible', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 2,
        phase: 'awaitingAuctionBid',
        currentPlayerId: 'player-host',
        auction: true,
        lastMutation: const <String, Object?>{
          'type': 'buyAuction',
          'commandId': 'cmd-bid-07',
        },
      ),
    );

    await tester.pumpWidget(_app(authority));

    expect(find.byKey(const ValueKey('live-auction')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-confirmed-buy-outcome')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('live-confirmed-auction-award')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('live-confirmed-auction-no-winner')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('live-safe-error')), findsNothing);
  });

  testWidgets('rejects malformed buy auction outcome data safely', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 2,
        phase: 'turnResolved',
        currentPlayerId: 'player-guest',
        lastMutation: _buyAuctionMutation(
          _outcome('propertyPurchased', <String, Object?>{
            'playerId': 'player-host',
            'propertyId': 'street-07',
            'price': '107',
          }),
        ),
        ownership: const <String, Object?>{
          'byPropertyId': <String, Object?>{'street-07': 'player-host'},
        },
      ),
    );

    await tester.pumpWidget(_app(authority));

    expect(find.text('Authority · invalidPublicGameSnapshot'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-confirmed-buy-outcome')),
      findsNothing,
    );
  });

  testWidgets('rejects a nonterminal buy auction outcome safely', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 2,
        phase: 'awaitingRoll',
        currentPlayerId: 'player-guest',
        lastMutation: _buyAuctionMutation(
          _outcome('propertyPurchased', <String, Object?>{
            'playerId': 'player-host',
            'propertyId': 'street-07',
            'price': 107,
          }),
        ),
        ownership: const <String, Object?>{
          'byPropertyId': <String, Object?>{'street-07': 'player-host'},
        },
      ),
    );

    await tester.pumpWidget(_app(authority));

    expect(find.text('Authority · invalidPublicGameSnapshot'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-confirmed-buy-outcome')),
      findsNothing,
    );
  });

  testWidgets('rejects a buy auction outcome inconsistent with ownership', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 2,
        phase: 'turnResolved',
        currentPlayerId: 'player-guest',
        lastMutation: _buyAuctionMutation(
          _outcome('auctionWon', <String, Object?>{
            'auctionId': 'auction-07',
            'propertyId': 'street-07',
            'winnerPlayerId': 'player-host',
            'winningBid': 40,
          }),
        ),
        ownership: const <String, Object?>{
          'byPropertyId': <String, Object?>{'street-07': 'player-guest'},
        },
      ),
    );

    await tester.pumpWidget(_app(authority));

    expect(find.text('Authority · invalidPublicGameSnapshot'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-confirmed-auction-award')),
      findsNothing,
    );
  });

  testWidgets('rejects an unawarded auction outcome with an owner', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority();
    addTearDown(authority.close);
    authority.emitLobby(gameId: 'game-live');
    authority.emitGame(
      _gameSnapshot(
        version: 2,
        phase: 'turnResolved',
        currentPlayerId: 'player-guest',
        lastMutation: _buyAuctionMutation(
          _outcome('auctionEndedWithoutWinner', <String, Object?>{
            'auctionId': 'auction-07',
            'propertyId': 'street-07',
          }),
        ),
        ownership: const <String, Object?>{
          'byPropertyId': <String, Object?>{'street-07': 'player-host'},
        },
      ),
    );

    await tester.pumpWidget(_app(authority));

    expect(find.text('Authority · invalidPublicGameSnapshot'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-confirmed-auction-no-winner')),
      findsNothing,
    );
  });
}

Widget _app(LiveFirstPlayableAuthority authority) => MaterialApp(
  theme: AppTheme.light,
  home: LiveFirstPlayableApp(authority: authority),
);

final class _FakeLiveAuthority implements LiveFirstPlayableAuthority {
  _FakeLiveAuthority({this.actorPlayerId = 'player-host'});

  final String actorPlayerId;
  final List<FirstPlayableAuthorityAction> actions = [];
  final StreamController<AuthorityPublicRoomSnapshot> _lobbyController =
      StreamController<AuthorityPublicRoomSnapshot>.broadcast();
  final StreamController<AuthorityPublicSnapshot> _gameController =
      StreamController<AuthorityPublicSnapshot>.broadcast();
  bool hostReady = false;
  bool gameStarted = false;
  FirstPlayableAuthorityOutcome rollOutcome =
      FirstPlayableAuthorityOutcome.accepted;
  FirstPlayableAuthorityOutcome reconnectOutcome =
      FirstPlayableAuthorityOutcome.accepted;
  Completer<AuthorityPublicRoomSnapshot>? refreshCompleter;
  bool failRefresh = false;
  String? lastInput;
  AuthorityPublicRoomSnapshot? _confirmedLobby;
  AuthorityPublicSnapshot? _confirmedGame;

  @override
  String? get latestCreatedRoomCode => 'ABC123';

  @override
  AuthorityPublicRoomSnapshot? get confirmedLobbySnapshot => _confirmedLobby;

  @override
  AuthorityPublicSnapshot? get confirmedGameSnapshot => _confirmedGame;

  @override
  bool requiresReconciliation = false;

  @override
  Stream<AuthorityPublicRoomSnapshot> get lobbySnapshots =>
      _lobbyController.stream;

  @override
  Stream<AuthorityPublicSnapshot> get gameSnapshots => _gameController.stream;

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async {
    actions.add(action);
    lastInput = input;
    if (action == FirstPlayableAuthorityAction.setReady &&
        actorPlayerId == 'player-host') {
      hostReady = true;
    }
    if (action == FirstPlayableAuthorityAction.startGame) gameStarted = true;
    final outcome = switch (action) {
      FirstPlayableAuthorityAction.roll => rollOutcome,
      FirstPlayableAuthorityAction.reconnect => reconnectOutcome,
      _ => FirstPlayableAuthorityOutcome.accepted,
    };
    if (action == FirstPlayableAuthorityAction.reconnect &&
        outcome != FirstPlayableAuthorityOutcome.uncertain &&
        outcome != FirstPlayableAuthorityOutcome.blocked) {
      requiresReconciliation = false;
    }
    return FirstPlayableAuthorityResult(outcome: outcome);
  }

  @override
  Future<AuthorityPublicRoomSnapshot> refreshLobby() async {
    final pendingRefresh = refreshCompleter;
    if (pendingRefresh != null) return pendingRefresh.future;
    if (failRefresh) throw StateError('snapshot unavailable');
    final snapshot = _lobbySnapshot(gameId: gameStarted ? 'game-live' : null);
    _confirmedLobby = snapshot;
    return snapshot;
  }

  void emitLobby({String? gameId, int? roomVersion}) {
    final snapshot = _lobbySnapshot(gameId: gameId, roomVersion: roomVersion);
    _confirmedLobby = snapshot;
    _lobbyController.add(snapshot);
  }

  void emitGame(AuthorityPublicSnapshot snapshot) {
    _confirmedGame = snapshot;
    _gameController.add(snapshot);
  }

  void emitGameError(Object error) => _gameController.addError(error);

  Future<void> close() async {
    await _lobbyController.close();
    await _gameController.close();
  }

  AuthorityPublicRoomSnapshot _lobbySnapshot({
    String? gameId,
    int? roomVersion,
  }) => AuthorityPublicRoomSnapshot(<String, Object?>{
    'schemaVersion': 1,
    'roomId': 'room-live',
    'roomVersion':
        roomVersion ??
        (gameId != null
            ? 4
            : hostReady
            ? 3
            : 2),
    'status': gameId == null ? 'open' : 'active',
    'hostPlayerId': 'player-host',
    'actorPlayerId': actorPlayerId,
    'presetId': 'express',
    'rulesVersion': 'synthetic-rules-vp0',
    'gameId': ?gameId,
    'members': <Object?>[
      <String, Object?>{
        'playerId': 'player-host',
        'kind': 'human',
        'ready': hostReady || gameId != null,
      },
      const <String, Object?>{
        'playerId': 'player-guest',
        'kind': 'human',
        'ready': true,
      },
    ],
  });
}

AuthorityPublicSnapshot _gameSnapshot({
  required int version,
  required String phase,
  required String currentPlayerId,
  bool propertyOffer = false,
  bool auction = false,
  List<int>? lastRoll,
  Map<String, Object?>? lastMutation,
  Map<String, Object?>? ownership,
}) => AuthorityPublicSnapshot(<String, Object?>{
  'schemaVersion': 1,
  'stateVersion': version,
  'gameId': 'game-live',
  'roomId': 'room-live',
  'status': 'active',
  'rulesVersion': 'synthetic-rules-vp0',
  'presetConfig': const <String, Object?>{'presetId': 'express'},
  'turnState': <String, Object?>{
    'phase': phase,
    'currentPlayerId': currentPlayerId,
    if (lastRoll != null)
      'lastRoll': <String, Object?>{
        'die1': lastRoll[0],
        'die2': lastRoll[1],
        'total': lastRoll[0] + lastRoll[1],
      },
  },
  if (propertyOffer)
    'pendingDecision': const <String, Object?>{
      'decisionId': 'decision-live',
      'kind': 'propertyOffer',
      'payload': <String, Object?>{
        'propertyId': 'property-placeholder',
        'purchasePrice': 100,
      },
      'allowedPlayerIds': <Object?>['player-host'],
    },
  if (auction)
    'activeAuction': const <String, Object?>{
      'auctionId': 'auction-live',
      'propertyId': 'property-placeholder',
      'currentBid': 10,
      'currentBidderPlayerId': 'player-host',
    },
  'lastMutation': ?lastMutation,
  'ownership': ?ownership,
});

Map<String, Object?> _buyAuctionMutation(Map<String, Object?> outcome) =>
    <String, Object?>{
      'type': 'buyAuction',
      'commandId': 'cmd-buy-auction',
      'outcome': outcome,
    };

Map<String, Object?> _outcome(String type, Map<String, Object?> data) =>
    <String, Object?>{'type': type, 'data': data};
