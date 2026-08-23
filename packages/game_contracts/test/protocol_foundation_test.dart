import 'package:board_game_contracts/game_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('input hash version starts at canonical version 1', () {
    expect(ProtocolFoundation.inputHashVersion, 1);
  });
}
