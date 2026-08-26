import 'dart:io';

import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/ui/first_playable/first_playable_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(_loadSdkFonts);

  const checkpoints = <(FirstPlayableStep, String)>[
    (FirstPlayableStep.home, 'home'),
    (FirstPlayableStep.createRoom, 'create_room'),
    (FirstPlayableStep.joinRoom, 'join_room'),
    (FirstPlayableStep.lobby, 'lobby'),
    (FirstPlayableStep.board, 'board'),
    (FirstPlayableStep.propertyOffer, 'property_offer'),
    (FirstPlayableStep.auction, 'auction'),
    (FirstPlayableStep.reconnect, 'reconnect'),
  ];

  for (final checkpoint in checkpoints) {
    testWidgets('Direction B ${checkpoint.$2} screenshot at 390x844', (
      tester,
    ) async {
      const viewport = Size(390, 844);
      final boundaryKey = ValueKey('golden-${checkpoint.$2}');
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _goldenTheme(),
          home: MediaQuery(
            data: const MediaQueryData(size: viewport, disableAnimations: true),
            child: RepaintBoundary(
              key: boundaryKey,
              child: FirstPlayableApp(initialStep: checkpoint.$1),
            ),
          ),
        ),
      );
      await tester.pump();

      await expectLater(
        find.byKey(boundaryKey),
        matchesGoldenFile('goldens/direction_b_${checkpoint.$2}_390x844.png'),
      );
    });
  }
}

Future<void> _loadSdkFonts() async {
  var flutterRoot = File(Platform.resolvedExecutable).parent;
  while (!Directory('${flutterRoot.path}/bin/cache/artifacts/material_fonts')
      .existsSync()) {
    if (flutterRoot.parent.path == flutterRoot.path) {
      throw StateError('No se encontró el SDK Flutter para cargar tipografía.');
    }
    flutterRoot = flutterRoot.parent;
  }

  Future<void> load(String family, String filename) async {
    final bytes = await File(
      '${flutterRoot.path}/bin/cache/artifacts/material_fonts/$filename',
    ).readAsBytes();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }

  await load('Roboto', 'Roboto-Regular.ttf');
  await load('MaterialIcons', 'MaterialIcons-Regular.otf');
}

ThemeData _goldenTheme() {
  final theme = AppTheme.light;
  const buttonText = WidgetStatePropertyAll<TextStyle>(
    TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w800),
  );
  const outlinedText = WidgetStatePropertyAll<TextStyle>(
    TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(textStyle: outlinedText),
    ),
  );
}
