import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'ui/first_playable/live_first_playable_app.dart';
import 'ui/first_playable/live_first_playable_ui_state.dart';
import 'ui/first_playable/live_first_playable_view_model.dart';

/// Tests may supply a path. Production preserves the platform's initial link.
final initialAppLocationProvider = Provider<String?>((ref) => null);

/// Routes are locators/presentation only. No redirect invokes a command, grants
/// membership, writes a device locator, or reconstructs a gameplay snapshot.
final appRouterProvider = Provider<GoRouter>(
  (ref) {
    final initialLocation = ref.watch(initialAppLocationProvider);
    final refresh = ValueNotifier<int>(0);
    ref.listen(liveFirstPlayableViewModelProvider, (_, _) {
      refresh.value += 1;
    });
    final router = GoRouter(
      initialLocation: initialLocation,
      overridePlatformDefaultLocation: initialLocation != null,
      refreshListenable: refresh,
      redirect: (context, route) {
        final segments = route.uri.pathSegments;
        // The view checks this requested game against confirmed membership.
        // Never redirect a foreign game locator into a partial game screen.
        if (segments.isNotEmpty &&
            (segments.first == 'game' || segments.first == 'resume')) {
          return null;
        }
        final state = ref.read(liveFirstPlayableViewModelProvider);
        final gameId = state.lobby?.gameId;
        if (gameId != null) return '/game/${Uri.encodeComponent(gameId)}';
        if (state.lobby != null && route.uri.path != '/lobby') return '/lobby';
        if (state.lobby == null && route.uri.path == '/lobby') return '/';
        return null;
      },
      errorBuilder: (_, _) =>
          const LiveFirstPlayableApp(routeError: 'routeUnavailable'),
      routes: [
        GoRoute(
          path: '/',
          name: 'home',
          pageBuilder: (_, state) => NoTransitionPage<void>(
            key: state.pageKey,
            child: const LiveFirstPlayableApp(
              entryStep: FirstPlayableStep.home,
            ),
          ),
          routes: [
            GoRoute(
              path: 'create',
              name: 'create',
              pageBuilder: (_, state) => NoTransitionPage<void>(
                key: state.pageKey,
                child: const LiveFirstPlayableApp(
                  entryStep: FirstPlayableStep.create,
                ),
              ),
            ),
            GoRoute(
              path: 'join',
              name: 'join',
              pageBuilder: (_, state) => NoTransitionPage<void>(
                key: state.pageKey,
                child: const LiveFirstPlayableApp(
                  entryStep: FirstPlayableStep.join,
                ),
              ),
            ),
            GoRoute(
              path: 'join/:roomCode',
              name: 'invite',
              pageBuilder: (_, state) {
                final code = state.pathParameters['roomCode']!;
                final valid = RegExp(r'^[A-Z0-9]{6}$').hasMatch(code);
                return NoTransitionPage<void>(
                  key: state.pageKey,
                  child: LiveFirstPlayableApp(
                    entryStep: FirstPlayableStep.join,
                    initialRoomCode: valid ? code : null,
                    routeError: valid ? null : 'invalidRoomCode',
                  ),
                );
              },
            ),
            GoRoute(
              path: 'lobby',
              name: 'lobby',
              pageBuilder: (_, state) => NoTransitionPage<void>(
                key: state.pageKey,
                child: const LiveFirstPlayableApp(
                  entryStep: FirstPlayableStep.lobby,
                ),
              ),
            ),
            for (final kind in ['game', 'resume'])
              GoRoute(
                path: '$kind/:gameId',
                name: kind,
                pageBuilder: (_, state) => NoTransitionPage<void>(
                  key: state.pageKey,
                  child: LiveFirstPlayableApp(
                    requestedGameId: state.pathParameters['gameId'],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
    ref.onDispose(() {
      router.dispose();
      refresh.dispose();
    });
    return router;
  },
  isAutoDispose: true,
  dependencies: [
    initialAppLocationProvider,
    liveFirstPlayableViewModelProvider,
  ],
);
