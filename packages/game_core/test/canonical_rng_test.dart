import 'package:board_game_core/game_core.dart';
import 'package:test/test.dart';

void main() {
  final seed = List<int>.generate(32, (index) => index);

  group('hmac_sha256_counter_v1', () {
    test('TV-22 matches all counter-zero HMAC blocks byte-for-byte', () {
      final rng = CanonicalRng(seed: seed);
      const expected = <RngStream, String>{
        RngStream.dice: 'cd0bff743cb69b414fbdf1b1bf835198965b3857095662ba3e7f79083fb0e5f8', // pragma: allowlist secret
        RngStream.seatOrder: 'fb0e8f4baf59fba7a4a3c6646b609007bdf17a883bfbbae6641dc107f163faa0', // pragma: allowlist secret
        RngStream.startingProperties: 'bcaa66fcd28ef7a7f441b965298be8ae4cfad37a57844f3bfd789a60bef13288', // pragma: allowlist secret
        RngStream.cardsAShuffle: '769ee472be5b61a744a526291af3e980f96a284faa66666f762e12121f37a83b', // pragma: allowlist secret
        RngStream.cardsBShuffle: 'e0c0e188e689fc5ba20e3fdad38b43aac3991ffd1ea1b7917a3769c430fe892e', // pragma: allowlist secret
      };

      for (final entry in expected.entries) {
        expect(rng.blockHexAt(entry.key, 0), entry.value);
      }
      expect(
        rng.commitmentHex,
        '677a0eaf9f0b68fa0c0fa5f102af287a4133203d07ea6c35317bfa56c65d9802', // pragma: allowlist secret
      );
    });

    test('TV-23 yields the canonical dice sequence and counter 12', () {
      var rng = CanonicalRng(seed: seed);
      final faces = <int>[];
      for (var index = 0; index < 12; index += 1) {
        final draw = rng.nextInt(RngStream.dice, 6);
        faces.add(draw.value + 1);
        rng = draw.successor;
      }

      expect(faces, <int>[6, 2, 2, 6, 5, 4, 1, 1, 3, 5, 3, 5]);
      expect(rng.counterFor(RngStream.dice), 12);
    });

    test('TV-24 yields the canonical seat order and counter 3', () {
      final shuffled = CanonicalRng(seed: seed)
          .shuffle(RngStream.seatOrder, <String>['P0', 'P1', 'P2', 'P3']);

      expect(shuffled.value, <String>['P2', 'P0', 'P1', 'P3']);
      expect(shuffled.successor.counterFor(RngStream.seatOrder), 3);
    });

    test('TV-25 yields the canonical cards A order and counter 9', () {
      final shuffled = CanonicalRng(seed: seed).shuffle(
        RngStream.cardsAShuffle,
        List<int>.generate(10, (index) => index),
      );

      expect(shuffled.value, <int>[4, 6, 7, 0, 9, 1, 2, 8, 5, 3]);
      expect(shuffled.successor.counterFor(RngStream.cardsAShuffle), 9);
    });

    test('TV-26 preserves stream independence', () {
      final initial = CanonicalRng(seed: seed);
      var diceOnly = initial;
      for (var index = 0; index < 37; index += 1) {
        diceOnly = diceOnly.nextInt(RngStream.dice, 6).successor;
      }

      final expected = initial.shuffle(
        RngStream.cardsAShuffle,
        List<int>.generate(10, (index) => index),
      );
      final actual = diceOnly.shuffle(
        RngStream.cardsAShuffle,
        List<int>.generate(10, (index) => index),
      );

      expect(actual.value, expected.value);
      expect(actual.successor.counterFor(RngStream.cardsAShuffle), 9);
      expect(actual.successor.counterFor(RngStream.dice), 37);
    });

    test(
      'TV-27 retry from identical private input is referentially stable',
      () {
        final snapshot = CanonicalRng(seed: seed);

        final firstAttempt = snapshot.nextInt(RngStream.dice, 6);
        final retriedCallback = snapshot.nextInt(RngStream.dice, 6);

        expect(retriedCallback.value, firstAttempt.value);
        expect(
          retriedCallback.successor.counterFor(RngStream.dice),
          firstAttempt.successor.counterFor(RngStream.dice),
        );
        expect(snapshot.counterFor(RngStream.dice), 0);
      },
    );

    test('TV-27 retry reproduces a multi-candidate rejection sequence', () {
      final snapshot = CanonicalRng(seed: seed);
      final bound = (BigInt.one << 63) + BigInt.one;

      final firstAttempt = snapshot.nextBigInt(RngStream.dice, bound);
      final retriedCallback = snapshot.nextBigInt(RngStream.dice, bound);

      expect(firstAttempt.candidatesConsumed, greaterThan(1));
      expect(retriedCallback.value, firstAttempt.value);
      expect(
        retriedCallback.successor.counterFor(RngStream.dice),
        firstAttempt.successor.counterFor(RngStream.dice),
      );
      expect(snapshot.counterFor(RngStream.dice), 0);
    });

    test('TV-28 rejects unknown and malformed stream labels', () {
      expect(
        () => RngStream.parse('cards_a'),
        throwsA(isA<RngContractViolation>()),
      );
      expect(
        () => RngStream.parse('Dice'),
        throwsA(isA<RngContractViolation>()),
      );
      expect(() => RngStream.parse(''), throwsA(isA<RngContractViolation>()));
    });

    test('TV-29 requires an exact 32-byte seed', () {
      expect(
        () => CanonicalRng(seed: List<int>.filled(31, 0)),
        throwsA(isA<RngContractViolation>()),
      );
      expect(
        () => CanonicalRng(seed: List<int>.filled(33, 0)),
        throwsA(isA<RngContractViolation>()),
      );
      expect(
        () => CanonicalRng(seed: <int>[...List<int>.filled(31, 0), 256]),
        throwsA(isA<RngContractViolation>()),
      );
    });

    test('TV-30 rejects invalid counters without wrap or source mutation', () {
      expect(
        () => CanonicalRng(seed: seed, counters: {RngStream.dice: -1}),
        throwsA(isA<RngContractViolation>()),
      );
      expect(
        () => CanonicalRng(
          seed: seed,
          counters: {RngStream.dice: maxPersistedRngCounter + 1},
        ),
        throwsA(isA<RngContractViolation>()),
      );

      final boundary = CanonicalRng(
        seed: seed,
        counters: {RngStream.dice: maxPersistedRngCounter},
      );
      expect(
        () => boundary.nextInt(RngStream.dice, 6),
        throwsA(isA<RngContractViolation>()),
      );
      expect(boundary.counterFor(RngStream.dice), maxPersistedRngCounter);
    });

    test('rejects invalid bounds before consuming a candidate', () {
      final rng = CanonicalRng(seed: seed);
      expect(
        () => rng.nextInt(RngStream.dice, 0),
        throwsA(isA<RngContractViolation>()),
      );
      expect(
        () => rng.nextBigInt(RngStream.dice, (BigInt.one << 64) + BigInt.one),
        throwsA(isA<RngContractViolation>()),
      );
      expect(rng.counterFor(RngStream.dice), 0);
    });

    test('matches the explicit starting-property bounded draws', () {
      var rng = CanonicalRng(seed: seed);
      final values = <int>[];
      for (var index = 0; index < 5; index += 1) {
        final draw = rng.nextInt(RngStream.startingProperties, 22);
        values.add(draw.value);
        rng = draw.successor;
      }
      expect(values, <int>[3, 4, 19, 15, 4]);
    });
  });
}
