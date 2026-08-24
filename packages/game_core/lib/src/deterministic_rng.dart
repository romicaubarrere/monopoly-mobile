import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const String canonicalRngVersion = 'hmac_sha256_counter_v1';

final BigInt _maxCounter = BigInt.from(9223372036854775807);
final BigInt _twoTo64 = BigInt.one << 64;

enum RngStream {
  dice('dice'),
  seatOrder('seat_order'),
  startingProperties('starting_properties'),
  cardsAShuffle('cards_a_shuffle'),
  cardsBShuffle('cards_b_shuffle');

  const RngStream(this.label);

  final String label;

  static RngStream parse(String label) => values.firstWhere(
    (stream) => stream.label == label,
    orElse: () => throw const FormatException('Unsupported RNG stream'),
  );
}

final class RngDraw<T> {
  const RngDraw({
    required this.value,
    required this.nextState,
    required this.candidatesConsumed,
  });

  final T value;
  final CanonicalRng nextState;
  final int candidatesConsumed;
}

/// Immutable authority-only implementation of `hmac_sha256_counter_v1`.
///
/// A draw returns a successor instead of mutating this instance. Transaction
/// callback retries from the same private snapshot therefore recompute the
/// same value and successor.
final class CanonicalRng {
  CanonicalRng({required List<int> seed, Map<RngStream, BigInt>? counters})
    : _seed = Uint8List.fromList(seed),
      _counters = Map.unmodifiable({
        for (final stream in RngStream.values)
          stream: counters?[stream] ?? BigInt.zero,
      }) {
    if (_seed.length != 32) {
      throw const FormatException('RNG seed must contain exactly 32 bytes');
    }
    for (final entry in _counters.entries) {
      _validateCounter(entry.value);
    }
  }

  final Uint8List _seed;
  final Map<RngStream, BigInt> _counters;

  BigInt counterFor(RngStream stream) => _counters[stream]!;

  String get commitmentHex {
    final payload = <int>[
      ...utf8.encode('monopoly-rng-v1-commit'),
      0,
      ..._seed,
    ];
    return sha256.convert(payload).toString();
  }

  List<int> blockFor(RngStream stream, BigInt counter) {
    _validateCounter(counter);
    final message = <int>[
      ...utf8.encode('monopoly-rng-v1'),
      0,
      ...utf8.encode(stream.label),
      0,
      ..._uint64BigEndian(counter),
    ];
    return Hmac(sha256, _seed).convert(message).bytes;
  }

  RngDraw<BigInt> nextInt(RngStream stream, BigInt upperBound) {
    if (upperBound < BigInt.one || upperBound > _twoTo64) {
      throw RangeError('upperBound must be between 1 and 2^64');
    }

    final limit = (_twoTo64 ~/ upperBound) * upperBound;
    var counter = counterFor(stream);
    var consumed = 0;
    while (true) {
      // Consuming max would require an unpersistable successor. Fail before
      // calculating or exposing any public result.
      if (counter >= _maxCounter) {
        throw StateError('RNG counter exhausted');
      }
      final raw = _raw64(blockFor(stream, counter));
      counter += BigInt.one;
      consumed += 1;
      if (raw < limit) {
        return RngDraw(
          value: raw % upperBound,
          nextState: _withCounter(stream, counter),
          candidatesConsumed: consumed,
        );
      }
    }
  }

  RngDraw<List<T>> shuffle<T>(RngStream stream, List<T> input) {
    final items = List<T>.of(input);
    var state = this;
    var consumed = 0;
    for (var index = items.length - 1; index >= 1; index -= 1) {
      final draw = state.nextInt(stream, BigInt.from(index + 1));
      final swapIndex = draw.value.toInt();
      final previous = items[index];
      items[index] = items[swapIndex];
      items[swapIndex] = previous;
      state = draw.nextState;
      consumed += draw.candidatesConsumed;
    }
    return RngDraw(
      value: List.unmodifiable(items),
      nextState: state,
      candidatesConsumed: consumed,
    );
  }

  CanonicalRng _withCounter(RngStream stream, BigInt counter) => CanonicalRng(
    seed: _seed,
    counters: {..._counters, stream: counter},
  );
}

void _validateCounter(BigInt counter) {
  if (counter < BigInt.zero || counter > _maxCounter) {
    throw const FormatException('RNG counter outside signed int64 range');
  }
}

List<int> _uint64BigEndian(BigInt value) {
  final bytes = Uint8List(8);
  var remaining = value;
  for (var index = 7; index >= 0; index -= 1) {
    bytes[index] = (remaining & BigInt.from(0xff)).toInt();
    remaining >>= 8;
  }
  return bytes;
}

BigInt _raw64(List<int> block) {
  var value = BigInt.zero;
  for (final byte in block.take(8)) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}
