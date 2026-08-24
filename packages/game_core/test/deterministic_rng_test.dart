import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  final testSeed = List<int>.generate(32, (index) => index);

  CanonicalRng rng({Map<RngStream, BigInt>? counters}) =>
      CanonicalRng(seed: testSeed, counters: counters);

  test('TV-22 primitive block KAT matches all streams', () {
    final source = rng();
    const expected = {
      RngStream.dice: 'cd0bff743cb69b414fbdf1b1bf835198965b3857095662ba3e7f79083fb0e5f8',
      RngStream.seatOrder: 'fb0e8f4baf59fba7a4a3c6646b609007bdf17a883bfbbae6641dc107f163faa0',
      RngStream.startingProperties: 'bcaa66fcd28ef7a7f441b965298be8ae4cfad37a57844f3bfd789a60bef13288',
      RngStream.cardsAShuffle: '769ee472be5b61a744a526291af3e980f96a284faa66666f762e12121f37a83b',
      RngStream.cardsBShuffle: 'e0c0e188e689fc5ba20e3fdad38b43aac3991ffd1ea1b7917a3769c430fe892e',
    };

    for (final entry in expected.entries) {
      expect(_hex(source.blockFor(entry.key, BigInt.zero)), entry.value);
    }
    expect(source.commitmentHex, '677a0eaf9f0b68fa0c0fa5f102af287a4133203d07ea6c35317bfa56c65d9802');
  });

  test('TV-23 dice KAT advances exactly twelve candidates', () {
    var state = rng();
    final faces = <int>[];
    for (var index = 0; index < 12; index += 1) {
      final draw = state.nextInt(RngStream.dice, BigInt.from(6));
      faces.add(draw.value.toInt() + 1);
      state = draw.nextState;
    }
    expect(faces, [6, 2, 2, 6, 5, 4, 1, 1, 3, 5, 3, 5]);
    expect(state.counterFor(RngStream.dice), BigInt.from(12));
  });

  test('TV-24 and TV-25 descending Fisher-Yates KATs', () {
    final seats = rng().shuffle(RngStream.seatOrder, ['P0', 'P1', 'P2', 'P3']);
    expect(seats.value, ['P2', 'P0', 'P1', 'P3']);
    expect(seats.nextState.counterFor(RngStream.seatOrder), BigInt.from(3));

    final cards = rng().shuffle(RngStream.cardsAShuffle, List<int>.generate(10, (i) => i));
    expect(cards.value, [4, 6, 7, 0, 9, 1, 2, 8, 5, 3]);
    expect(cards.nextState.counterFor(RngStream.cardsAShuffle), BigInt.from(9));
  });

  test('TV-26 streams stay independent', () {
    var changedDice = rng();
    for (var index = 0; index < 17; index += 1) {
      changedDice = changedDice.nextInt(RngStream.dice, BigInt.from(6)).nextState;
    }
    final cards = changedDice.shuffle(
      RngStream.cardsAShuffle,
      List<int>.generate(10, (i) => i),
    );
    expect(cards.value, [4, 6, 7, 0, 9, 1, 2, 8, 5, 3]);
    expect(cards.nextState.counterFor(RngStream.dice), BigInt.from(17));
    expect(cards.nextState.counterFor(RngStream.cardsAShuffle), BigInt.from(9));
  });

  test('TV-28 and TV-29 reject unknown stream and invalid seed', () {
    expect(() => RngStream.parse('cards_c_shuffle'), throwsFormatException);
    expect(() => CanonicalRng(seed: List.filled(31, 0)), throwsFormatException);
    expect(() => CanonicalRng(seed: List.filled(33, 0)), throwsFormatException);
  });

  test('TV-30 signed-int64 boundary fails before public output', () {
    expect(
      () => rng(counters: {RngStream.dice: BigInt.from(-1)}),
      throwsFormatException,
    );
    expect(
      () => rng(counters: {RngStream.dice: BigInt.one << 63}),
      throwsFormatException,
    );
    final exhausted = rng(
      counters: {RngStream.dice: BigInt.from(9223372036854775807)},
    );
    expect(
      () => exhausted.nextInt(RngStream.dice, BigInt.from(6)),
      throwsStateError,
    );
    expect(
      exhausted.counterFor(RngStream.dice),
      BigInt.from(9223372036854775807),
    );
  });

  test('identical private snapshots recompute identical output and successor', () {
    final first = rng().nextInt(RngStream.startingProperties, BigInt.from(22));
    final retry = rng().nextInt(RngStream.startingProperties, BigInt.from(22));
    expect(first.value, BigInt.from(3));
    expect(retry.value, first.value);
    expect(
      retry.nextState.counterFor(RngStream.startingProperties),
      first.nextState.counterFor(RngStream.startingProperties),
    );
  });
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
