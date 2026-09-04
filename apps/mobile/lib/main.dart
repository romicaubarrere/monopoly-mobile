import 'package:flutter/material.dart';

import 'design_system/app_theme.dart';
import 'infrastructure/mobile_authority_bootstrap.dart';
import 'ui/first_playable/live_first_playable_app.dart';

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
  const BoardGameApp({super.key, required this.authority});

  final LiveFirstPlayableAuthority authority;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'La Vuelta',
      theme: AppTheme.light,
      home: LiveFirstPlayableApp(authority: authority),
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
