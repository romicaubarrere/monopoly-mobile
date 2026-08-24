import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const String canonicalRngVersion = 'hmac_sha256_counter_v1';
const int maxPersistedRngCounter = 0x7fffffffffffffff;

enum RngStream {
  dice('dice'),
  seatOrder('seat_order'),
  startingProperties('starting_properties'),
  cardsAShuffle('cards_a_shuffle'),
  cardsBShuffle('cards_b_shuffle');

  const RngStream(this.label);

  final String label;

  static RngStream parse(String label) {
    for (final stream in values) {
      if (stream.label == label) {
        return stream;
      }
    }
    throw RngContractViolation('Unknown RNG stream: $label');
  }
}

final class RngContractViolation implements Exception {
  const RngContractViolation(this.message);

  final String message;

  @override
  String toString() => 'RngContractViolation: $message';
}

final class RngTransition<T> {
  const RngTransition({
    required this.value,
    required this.successor,
    required this.candidatesConsumed,
  });

  final T value;
  final CanonicalRng successor;
  final int candidatesConsumed;
}

/// Immutable authority-side state for the canonical M1 random generator.
///
/// A draw returns a successor instead of mutating this object. Transaction
/// callback retries from the same private snapshot therefore recompute the same
/// value and successor; only the accepted transaction persists the successor.
final class CanonicalRng {
  factory CanonicalRng({
    required List<int> seed,
    Map<RngStream, int> counters = const {},
  }) {
    if (seed.length != 32) {
      throw RngContractViolation(
        'Seed must contain exactly 32 bytes; got ${seed.length}',
      );
    }
    if (seed.any((byte) => byte < 0 || byte > 255)) {
      throw const RngContractViolation('Seed contains a non-byte value');
    }

    final normalizedCounters = <RngStream, int>{};
    for (final stream in RngStream.values) {
      final counter = counters[stream] ?? 0;
      _validateCounter(counter);
      normalizedCounters[stream] = counter;
    }

    return CanonicalRng._(
      Uint8List.fromList(seed),
      Map.unmodifiable(normalizedCounters),
    );
  }

  const CanonicalRng._(this._seed, this._counters);

  static final Uint8List _domain = Uint8List.fromList(
    utf8.encode('monopoly-rng-v1'),
  );
  static final Uint8List _commitmentDomain = Uint8List.fromList(
    utf8.encode('monopoly-rng-v1-commit'),
  );
  static final BigInt _uint64Cardinality = BigInt.one << 64;

  final Uint8List _seed;
  final Map<RngStream, int> _counters;

  int counterFor(RngStream stream) => _counters[stream]!;

  String get commitmentHex {
    final digest = sha256.convert(<int>[..._commitmentDomain, 0, ..._seed]);
    return _hex(digest.bytes);
  }

  /// Produces the byte-exact HMAC block at an explicit persisted counter.
  ///
  /// This authority/core primitive exists for cross-language KAT verification.
  /// Raw blocks must never be logged, serialized into public state, or exposed
  /// through mobile contracts.
  Uint8List blockAt(RngStream stream, int counter) {
    _validateCounter(counter);
    final message = <int>[
      ..._domain,
      0,
      ...utf8.encode(stream.label),
      0,
      ..._uint64BigEndian(counter),
    ];
    return Uint8List.fromList(Hmac(sha256, _seed).convert(message).bytes);
  }

  String blockHexAt(RngStream stream, int counter) =>
      _hex(blockAt(stream, counter));

  RngTransition<int> nextInt(RngStream stream, int upperBound) {
    final transition = nextBigInt(stream, BigInt.from(upperBound));
    return RngTransition(
      value: transition.value.toInt(),
      successor: transition.successor,
      candidatesConsumed: transition.candidatesConsumed,
    );
  }

  RngTransition<BigInt> nextBigInt(RngStream stream, BigInt upperBound) {
    if (upperBound < BigInt.one || upperBound > _uint64Cardinality) {
      throw RngContractViolation(
        'upperBound must be within 1..2^64; got $upperBound',
      );
    }

    final limit = (_uint64Cardinality ~/ upperBound) * upperBound;
    var candidateCounter = counterFor(stream);
    var consumed = 0;

    while (true) {
      // Counter semantics require persisting the next candidate. Consuming the
      // maximum signed int64 value would require an unrepresentable successor,
      // so the whole immutable transition fails before any public mutation.
      if (candidateCounter == maxPersistedRngCounter) {
        throw const RngContractViolation(
          'RNG counter successor exceeds signed int64 persistence boundary',
        );
      }

      final raw64 = _unsigned64(blockAt(stream, candidateCounter));
      candidateCounter += 1;
      consumed += 1;
      if (raw64 >= limit) {
        continue;
      }

      final successorCounters = Map<RngStream, int>.from(_counters)
        ..[stream] = candidateCounter;
      return RngTransition(
        value: raw64 % upperBound,
        successor: CanonicalRng._(_seed, Map.unmodifiable(successorCounters)),
        candidatesConsumed: consumed,
      );
    }
  }

  RngTransition<List<T>> shuffle<T>(RngStream stream, List<T> input) {
    final items = List<T>.from(input);
    var current = this;
    var consumed = 0;
    for (var index = items.length - 1; index >= 1; index -= 1) {
      final draw = current.nextInt(stream, index + 1);
      current = draw.successor;
      consumed += draw.candidatesConsumed;
      final swapIndex = draw.value;
      final item = items[index];
      items[index] = items[swapIndex];
      items[swapIndex] = item;
    }
    return RngTransition(
      value: List.unmodifiable(items),
      successor: current,
      candidatesConsumed: consumed,
    );
  }

  static void _validateCounter(int counter) {
    if (counter < 0 || counter > maxPersistedRngCounter) {
      throw RngContractViolation(
        'Counter must be within signed int64 range; got $counter',
      );
    }
  }

  static List<int> _uint64BigEndian(int value) => List<int>.generate(
    8,
    (index) => (value >> ((7 - index) * 8)) & 0xff,
    growable: false,
  );

  static BigInt _unsigned64(List<int> block) {
    var value = BigInt.zero;
    for (var index = 0; index < 8; index += 1) {
      value = (value << 8) | BigInt.from(block[index]);
    }
    return value;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
