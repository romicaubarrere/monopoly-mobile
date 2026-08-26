import 'package:flutter/material.dart';

import 'design_system/app_theme.dart';
import 'ui/first_playable/first_playable_app.dart';

void main() {
  runApp(const BoardGameApp());
}

class BoardGameApp extends StatelessWidget {
  const BoardGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'La Vuelta',
      theme: AppTheme.light,
      home: const FirstPlayableApp(),
    );
  }
}
