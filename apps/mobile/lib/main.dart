import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_router.dart';
import 'design_system/app_theme.dart';
import 'infrastructure/mobile_authority_bootstrap.dart';
import 'ui/first_playable/live_first_playable_app.dart';
import 'ui/first_playable/live_first_playable_view_model.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final authority = await MobileAuthorityBootstrap.fromEnvironment();
    runApp(
      BoardGameApp(authority: ClientLiveFirstPlayableAuthority(authority)),
    );
  } on Object catch (error, stackTrace) {
    debugPrint('Mobile authority bootstrap failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    runApp(const BoardGameConfigurationErrorApp());
  }
}

class BoardGameApp extends StatelessWidget {
  const BoardGameApp({
    super.key,
    required this.authority,
    this.initialLocation,
  });

  final LiveFirstPlayableAuthority authority;
  final String? initialLocation;

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [
      liveFirstPlayableAuthorityProvider.overrideWithValue(authority),
      initialAppLocationProvider.overrideWithValue(initialLocation),
    ],
    child: const _RoutedBoardGameApp(),
  );
}

class _RoutedBoardGameApp extends ConsumerWidget {
  const _RoutedBoardGameApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'La Vuelta',
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}

class BoardGameConfigurationErrorApp extends StatelessWidget {
  const BoardGameConfigurationErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'La Vuelta',
      theme: AppTheme.light,
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No se pudo conectar con la partida. Revisá la configuración segura del entorno.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
