import 'package:board_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile-first shell renders primary entry actions', (
    tester,
  ) async {
    await tester.pumpWidget(const BoardGameApp());

    expect(find.text('Una vuelta más.\nUna historia nueva.'), findsOneWidget);
    expect(find.text('Crear partida'), findsOneWidget);
    expect(find.text('Unirse con código'), findsOneWidget);
    expect(find.text('PRIMERA VUELTA'), findsOneWidget);
    expect(find.textContaining('DEC-065'), findsOneWidget);
  });
}
