import 'package:board_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile-first shell renders primary entry actions', (tester) async {
    await tester.pumpWidget(const BoardGameApp());

    expect(find.text('Una partida que entra en una mano.'), findsOneWidget);
    expect(find.text('Crear partida'), findsOneWidget);
    expect(find.text('Unirse con código'), findsOneWidget);
    expect(find.text('Shell de partida'), findsOneWidget);
  });
}
