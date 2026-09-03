import 'package:board_backend_api/backend_api.dart';
import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/first_playable/live_first_playable_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'created room renders Authority code and confirmed two-member lobby',
    (tester) async {
      final authority = _FakeLiveAuthority();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LiveFirstPlayableApp(authority: authority),
        ),
      );

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

      await tester.tap(find.text('Estoy lista'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('player-host · human · Listo'),
        findsOneWidget,
      );

      await tester.tap(find.text('Empezar partida'));
      await tester.pumpAndSettle();
      expect(find.text('La vuelta está en marcha'), findsOneWidget);

      await tester.tap(find.text('Tirar dados'));
      await tester.pumpAndSettle();
      expect(find.text('Decisión confirmada'), findsOneWidget);

      await tester.tap(find.text('No comprar · abrir subasta'));
      await tester.pumpAndSettle();
      expect(find.text('Subasta autoritativa'), findsOneWidget);

      await tester.tap(find.text('Pasar'));
      await tester.pumpAndSettle();
      expect(find.text('Recuperá el estado confirmado'), findsOneWidget);

      await tester.tap(find.text('Reconciliar'));
      await tester.pumpAndSettle();
      expect(find.text('La vuelta está en marcha'), findsOneWidget);
    },
  );

  testWidgets('join keeps entered Authority room code in confirmed lobby', (
    tester,
  ) async {
    final authority = _FakeLiveAuthority(actorPlayerId: 'player-guest');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: LiveFirstPlayableApp(authority: authority),
      ),
    );

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
}

final class _FakeLiveAuthority implements LiveFirstPlayableAuthority {
  _FakeLiveAuthority({this.actorPlayerId = 'player-host'});

  final String actorPlayerId;
  bool hostReady = false;
  String? lastInput;

  @override
  String? get latestCreatedRoomCode => 'ABC123';

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async {
    lastInput = input;
    if (action == FirstPlayableAuthorityAction.setReady &&
        actorPlayerId == 'player-host') {
      hostReady = true;
    }
    return const FirstPlayableAuthorityResult(
      outcome: FirstPlayableAuthorityOutcome.accepted,
    );
  }

  @override
  Future<AuthorityPublicRoomSnapshot> refreshLobby() async =>
      AuthorityPublicRoomSnapshot(<String, Object?>{
        'schemaVersion': 1,
        'roomId': 'room-live',
        'roomVersion': hostReady ? 3 : 2,
        'status': 'open',
        'hostPlayerId': 'player-host',
        'actorPlayerId': actorPlayerId,
        'presetId': 'express',
        'rulesVersion': 'synthetic-rules-vp0',
        'members': <Object?>[
          <String, Object?>{
            'playerId': 'player-host',
            'kind': 'human',
            'ready': hostReady,
          },
          const <String, Object?>{
            'playerId': 'player-guest',
            'kind': 'human',
            'ready': true,
          },
        ],
      });
}
