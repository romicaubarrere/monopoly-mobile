import 'package:flutter/material.dart';
import 'package:board_backend_api/backend_api.dart';

import 'design_system/app_theme.dart';
import 'infrastructure/mobile_authority_bootstrap.dart';
import 'ui/first_playable/first_playable_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final authority = await MobileAuthorityBootstrap.fromEnvironment();
    runApp(BoardGameApp(authority: authority));
  } on Object {
    runApp(const BoardGameConfigurationErrorApp());
  }
}

class BoardGameApp extends StatelessWidget {
  const BoardGameApp({super.key, this.authority});

  final FirstPlayableAuthorityBinding? authority;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'La Vuelta',
      theme: AppTheme.light,
      home: FirstPlayableApp(authority: authority),
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
