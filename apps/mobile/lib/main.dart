import 'package:flutter/material.dart';

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
      home: Scaffold(
        body: Center(
          child: Semantics(
            headingLevel: 1,
            child: const Text('Board Game'),
          ),
        ),
      ),
    );
  }
}
