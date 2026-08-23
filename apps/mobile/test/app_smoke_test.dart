import 'package:board_mobile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app shell renders its rebrandable heading', (tester) async {
    await tester.pumpWidget(const BoardGameApp());
    expect(find.text('Board Game'), findsOneWidget);
  });
}
