import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/main.dart';
import 'package:board_mobile/ui/first_playable/live_first_playable_app.dart';
import 'package:board_mobile/ui/first_playable/live_first_playable_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/live_authority_fixture.dart';

void main() {
  test(
    'derived membership and action lists cannot mutate confirmed presentation',
    () async {
      final authority = _startedAuthority();
      final container = _container(authority);
      authority.emitGame(
        gameSnapshot(
          version: 1,
          phase: 'awaitingPropertyDecision',
          currentPlayerId: 'player-host',
          propertyOffer: true,
        ),
      );
      await _drain();
      final state = container.read(liveFirstPlayableViewModelProvider);
      expect(() => state.lobby!.members.clear(), throwsUnsupportedError);
      expect(
        () => state.game!.propertyOffer!.allowedPlayerIds[0] = 'other',
        throwsUnsupportedError,
      );
      expect(state.game!.canResolveProperty, isTrue);
    },
  );

  test('repeated confirmed result snapshots never apply a second visible transition', () async {
    final authority = _startedAuthority();
    final container = _container(authority);
    final snapshot = gameSnapshot(
      version: 1,
      phase: 'awaitingPropertyDecision',
      currentPlayerId: 'player-host',
      propertyOffer: true,
    );
    authority.emitGame(snapshot);
    await _drain();
    final first = container.read(liveFirstPlayableViewModelProvider);
    authority.emitGame(snapshot);
    await _drain();
    final duplicate = container.read(liveFirstPlayableViewModelProvider);
    expect(duplicate.game!.stateVersion, first.game!.stateVersion);
    expect(duplicate.confirmedGameSnapshot, same(first.confirmedGameSnapshot));
    expect(
      duplicate.game!.propertyOffer!.purchasePrice,
      first.game!.propertyOffer!.purchasePrice,
    );
    expect(authority.actions, isEmpty);
  });

  test('ViewModel changes only pending before ACK and waits for a snapshot after ACK', () async {
    final authority = _startedAuthority();
    final container = _container(authority);
    final before = container.read(liveFirstPlayableViewModelProvider);
    final completer = Completer<FirstPlayableAuthorityResult>();
    authority.performCompleter = completer;
    final model = container.read(liveFirstPlayableViewModelProvider.notifier);
    final pending = model.roll();
    final during = container.read(liveFirstPlayableViewModelProvider);
    expect(during.busy, isTrue);
    expect(during.confirmedGameSnapshot, same(before.confirmedGameSnapshot));
    expect(during.game, same(before.game));
    await model.roll();
    expect(authority.actions, [FirstPlayableAuthorityAction.roll]);
    completer.complete(
      const FirstPlayableAuthorityResult(
        outcome: FirstPlayableAuthorityOutcome.accepted,
      ),
    );
    await pending;
    final acknowledged = container.read(liveFirstPlayableViewModelProvider);
    expect(acknowledged.busy, isFalse);
    expect(
      acknowledged.confirmedGameSnapshot,
      same(before.confirmedGameSnapshot),
    );
    expect(acknowledged.game!.stateVersion, 0);
    final replacement = gameSnapshot(
      version: 1,
      phase: 'awaitingPropertyDecision',
      currentPlayerId: 'player-host',
      propertyOffer: true,
    );
    authority.emitGame(replacement);
    await _drain();
    expect(
      container.read(liveFirstPlayableViewModelProvider).confirmedGameSnapshot,
      same(replacement),
    );
    expect(
      container.read(liveFirstPlayableViewModelProvider).game!.stateVersion,
      1,
    );
  });

  test(
    'snapshot replacement invalidates the old pending sheet without a route',
    () async {
      final authority = _startedAuthority();
      final container = _container(authority);
      authority.emitGame(
        gameSnapshot(
          version: 1,
          phase: 'awaitingPropertyDecision',
          currentPlayerId: 'player-host',
          propertyOffer: true,
        ),
      );
      await _drain();
      final offered = container.read(liveFirstPlayableViewModelProvider);
      expect(offered.game!.propertyOffer, isNotNull);
      expect(
        (offered.confirmedGameSnapshot!.snapshot['pendingDecision']
            as Map)['decisionId'],
        'decision-live',
      );
      authority.emitGame(
        gameSnapshot(
          version: 2,
          phase: 'awaitingAuctionBid',
          currentPlayerId: 'player-host',
          auction: true,
        ),
      );
      await _drain();
      final auction = container.read(liveFirstPlayableViewModelProvider);
      expect(auction.game!.propertyOffer, isNull);
      expect(auction.game!.auction, isNotNull);
      expect(
        auction.confirmedGameSnapshot!.snapshot.containsKey('pendingDecision'),
        isFalse,
      );
      expect(authority.actions, isEmpty);
    },
  );

  test('provider recreation restores confirmed state and retains uncertain identity', () async {
    final authority = _startedAuthority();
    authority.requiresReconciliation = true;
    final container = _container(authority);
    final original = container
        .read(liveFirstPlayableViewModelProvider)
        .confirmedGameSnapshot;
    container.invalidate(liveFirstPlayableViewModelProvider);
    final rebuilt = container.read(liveFirstPlayableViewModelProvider);
    expect(rebuilt.confirmedGameSnapshot, same(original));
    expect(rebuilt.reconnectRequired, isTrue);
    expect(authority.actions, isEmpty);
  });

  test(
    'late command completion cannot populate a replaced authority provider',
    () async {
      final oldAuthority = _startedAuthority();
      final container = _container(oldAuthority);
      final completer = Completer<FirstPlayableAuthorityResult>();
      oldAuthority.performCompleter = completer;
      final pending = container
          .read(liveFirstPlayableViewModelProvider.notifier)
          .roll();
      final replacement = FakeLiveAuthority();
      addTearDown(replacement.close);
      container.updateOverrides([
        liveFirstPlayableAuthorityProvider.overrideWithValue(replacement),
      ]);
      expect(container.read(liveFirstPlayableViewModelProvider).game, isNull);
      completer.complete(
        const FirstPlayableAuthorityResult(
          outcome: FirstPlayableAuthorityOutcome.uncertain,
        ),
      );
      await pending;
      final current = container.read(liveFirstPlayableViewModelProvider);
      expect(current.game, isNull);
      expect(current.busy, isFalse);
      expect(current.reconnectRequired, isFalse);
    },
  );

  testWidgets('Riverpod override renders a confirmed Board without Firebase', (
    tester,
  ) async {
    final authority = _startedAuthority();
    addTearDown(authority.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          liveFirstPlayableAuthorityProvider.overrideWithValue(authority),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const LiveFirstPlayableApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-board')), findsOneWidget);
    expect(authority.actions, isEmpty);
  });

  testWidgets(
    'invite deep link prefills only and submits through the existing Authority port',
    (tester) async {
      final authority = FakeLiveAuthority();
      addTearDown(authority.close);
      await tester.pumpWidget(
        BoardGameApp(authority: authority, initialLocation: '/join/ABC123'),
      );
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('live-room-code-input')),
      );
      expect(field.controller!.text, 'ABC123');
      expect(authority.actions, isEmpty);
      expect(authority.refreshCalls, 0);
      await tester.tap(find.text('Unirse'));
      await tester.pumpAndSettle();
      expect(authority.actions, [FirstPlayableAuthorityAction.joinRoom]);
      expect(authority.lastInput, 'ABC123');
      expect(find.byKey(const ValueKey('live-lobby')), findsOneWidget);
    },
  );

  for (final path in [
    '/game/foreign',
    '/resume/foreign',
    '/join/invalid',
    '/unknown',
  ]) {
    testWidgets('$path cannot establish membership or render a partial board', (
      tester,
    ) async {
      final authority = FakeLiveAuthority();
      addTearDown(authority.close);
      await tester.pumpWidget(
        BoardGameApp(authority: authority, initialLocation: path),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('live-route-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('live-board')), findsNothing);
      expect(find.byKey(const ValueKey('live-game-loading')), findsNothing);
      expect(authority.actions, isEmpty);
      expect(authority.refreshCalls, 0);
    });
  }

  testWidgets('a foreign game link does not show the other confirmed session', (
    tester,
  ) async {
    final authority = _startedAuthority();
    addTearDown(authority.close);
    await tester.pumpWidget(
      BoardGameApp(authority: authority, initialLocation: '/game/foreign'),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('live-route-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('live-board')), findsNothing);
    expect(authority.actions, isEmpty);
  });

  testWidgets(
    'confirmed resume route keeps reconnect as board state and foreground does not replay',
    (tester) async {
      final authority = _startedAuthority()..requiresReconciliation = true;
      addTearDown(authority.close);
      await tester.pumpWidget(
        BoardGameApp(
          authority: authority,
          initialLocation: '/resume/game-live',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-reconnect')), findsOneWidget);
      final context = tester.element(
        find.byKey(const ValueKey('live-reconnect')),
      );
      final router = GoRouter.of(context);
      expect(
        router.routeInformationProvider.value.uri.path,
        '/resume/game-live',
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('live-reconnect')), findsOneWidget);
      expect(authority.actions, isEmpty);
    },
  );

  testWidgets('new decision changes the sheet but never the game URL', (
    tester,
  ) async {
    final authority = _startedAuthority();
    addTearDown(authority.close);
    await tester.pumpWidget(BoardGameApp(authority: authority));
    await tester.pumpAndSettle();
    final router = GoRouter.of(
      tester.element(find.byKey(const ValueKey('live-board'))),
    );
    expect(router.routeInformationProvider.value.uri.path, '/game/game-live');
    authority.emitGame(
      gameSnapshot(
        version: 1,
        phase: 'awaitingPropertyDecision',
        currentPlayerId: 'player-host',
        propertyOffer: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-property')), findsOneWidget);
    authority.emitGame(
      gameSnapshot(
        version: 2,
        phase: 'awaitingAuctionBid',
        currentPlayerId: 'player-host',
        auction: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-property')), findsNothing);
    expect(find.byKey(const ValueKey('live-auction')), findsOneWidget);
    expect(router.routeInformationProvider.value.uri.path, '/game/game-live');
  });

  testWidgets('system back from room entry returns to Home without a command', (
    tester,
  ) async {
    final authority = FakeLiveAuthority();
    addTearDown(authority.close);
    await tester.pumpWidget(
      BoardGameApp(authority: authority, initialLocation: '/create'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-create')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Crear partida'), findsOneWidget);
    expect(authority.actions, isEmpty);
  });

  for (final layout in [
    (size: const Size(375, 812), scale: 1.3),
    (size: const Size(812, 375), scale: 2.0),
  ]) {
    testWidgets(
      'safe access remains reachable at ${layout.size} and ${layout.scale} text scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = layout.size;
        tester.platformDispatcher.textScaleFactorTestValue = layout.scale;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        final semantics = tester.ensureSemantics();
        try {
          final authority = FakeLiveAuthority();
          addTearDown(authority.close);
          await tester.pumpWidget(
            BoardGameApp(
              authority: authority,
              initialLocation: '/game/foreign',
            ),
          );
          await tester.pumpAndSettle();
          final back = find.widgetWithText(FilledButton, 'Volver al inicio');
          await tester.ensureVisible(back);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
          expect(find.bySemanticsLabel('Volver al inicio'), findsOneWidget);
          expect(MediaQuery.disableAnimationsOf(tester.element(back)), isTrue);
          expect(
            MediaQuery.textScalerOf(tester.element(back)).scale(10),
            layout.scale * 10,
          );
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          final router = GoRouter.of(tester.element(back));
          await tester.tap(back);
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, '/');
          expect(authority.actions, isEmpty);
          expect(authority.refreshCalls, 0);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}

FakeLiveAuthority _startedAuthority() => FakeLiveAuthority()
  ..emitLobby(gameId: 'game-live')
  ..emitGame(
    gameSnapshot(
      version: 0,
      phase: 'awaitingRoll',
      currentPlayerId: 'player-host',
    ),
  );

ProviderContainer _container(FakeLiveAuthority authority) {
  addTearDown(authority.close);
  final container = ProviderContainer(
    overrides: [
      liveFirstPlayableAuthorityProvider.overrideWithValue(authority),
    ],
  );
  addTearDown(container.dispose);
  final subscription = container.listen(
    liveFirstPlayableViewModelProvider,
    (_, _) {},
  );
  addTearDown(subscription.close);
  return container;
}

Future<void> _drain() => Future<void>.delayed(Duration.zero);
