import 'package:board_mobile/design_system/app_theme.dart';
import 'package:board_mobile/design_system/tokens.dart';
import 'package:board_mobile/design_system/visual_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Direction B character and improvement identities are explicit', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Wrap(
            children: [
              CharacterArtSlot(identity: CharacterIdentity.mani),
              CharacterArtSlot(identity: CharacterIdentity.almendra),
              CharacterArtSlot(identity: CharacterIdentity.phillip),
              CharacterArtSlot(identity: CharacterIdentity.manis),
              CharacterArtSlot(identity: CharacterIdentity.popon),
            ],
          ),
        ),
      ),
    );

    for (final anatomy in [
      'Perra clara, cruza labradora, orejas canela',
      'Gata tuxedo',
      'Gato naranja atigrado',
      'Mejoras · arte final pendiente',
      'Quinta mejora máxima · no mascota',
    ]) {
      expect(find.bySemanticsLabel(RegExp(anatomy)), findsOneWidget);
    }

    semantics.dispose();
  });

  test('Direction B semantic tokens remain the approved palette', () {
    expect(AppPalette.primary, const Color(0xFF3F7D61));
    expect(AppPalette.canvas, const Color(0xFFF7F0E4));
    expect(AppPalette.coral, const Color(0xFFEE7B69));
    expect(AppPalette.violet, const Color(0xFF765A9B));
  });
}
