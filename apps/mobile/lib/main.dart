import 'package:flutter/material.dart';

import 'design_system/app_theme.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const BoardGameApp());
}

class BoardGameApp extends StatelessWidget {
  const BoardGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Board Game',
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }
}
