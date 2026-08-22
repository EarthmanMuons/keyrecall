import 'dart:math' as math;
import 'dart:typed_data';

const int _n = 624;
const int _m = 397;
const int _matrixA = 0x9908b0df;
const int _upperMask = 0x80000000;
const int _lowerMask = 0x7fffffff;
const int _mask32 = 0xffffffff;
const double _twoPi = 2 * math.pi;

/// A Mersenne Twister that reproduces CPython's `random.Random` stream
/// exactly.
///
/// The Python prototype under `analysis/` is the reference implementation of
/// the V1 learner model and scheduler, and its synthetic runs are the recorded
/// behavior this port is checked against. Drawing the same numbers in the same
/// order is what makes those runs comparable attempt by attempt, rather than
/// only in distribution.
///
/// This is a simulation tool, not a source of randomness for anything that
/// needs to be unpredictable. It requires 64-bit integers, so it runs on
/// native targets rather than the web.
class PythonCompatibleRandom {
  final Uint32List _state = Uint32List(_n);
  int _index = _n;
  double? _pendingGaussian;

  /// A generator seeded the way `random.Random(seed)` is.
  PythonCompatibleRandom(int seed) {
    _seedByKey(_keyFor(seed));
  }

  /// The 32-bit little-endian key CPython derives from an integer seed.
  static List<int> _keyFor(int seed) {
    var magnitude = seed.abs();
    if (magnitude == 0) return [0];
    final key = <int>[];
    while (magnitude > 0) {
      key.add(magnitude & _mask32);
      magnitude >>= 32;
    }
    return key;
  }

  void _initialize(int seed) {
    _state[0] = seed & _mask32;
    for (var i = 1; i < _n; i++) {
      final previous = _state[i - 1];
      _state[i] = (1812433253 * (previous ^ (previous >> 30)) + i) & _mask32;
    }
    _index = _n;
  }

  void _seedByKey(List<int> key) {
    _initialize(19650218);
    var i = 1;
    var j = 0;
    for (var k = math.max(_n, key.length); k > 0; k--) {
      final previous = _state[i - 1];
      _state[i] =
          ((_state[i] ^ ((previous ^ (previous >> 30)) * 1664525)) +
              key[j] +
              j) &
          _mask32;
      i++;
      j++;
      if (i >= _n) {
        _state[0] = _state[_n - 1];
        i = 1;
      }
      if (j >= key.length) j = 0;
    }
    for (var k = _n - 1; k > 0; k--) {
      final previous = _state[i - 1];
      _state[i] =
          ((_state[i] ^ ((previous ^ (previous >> 30)) * 1566083941)) - i) &
          _mask32;
      i++;
      if (i >= _n) {
        _state[0] = _state[_n - 1];
        i = 1;
      }
    }
    _state[0] = _upperMask;
  }

  void _twist() {
    for (var i = 0; i < _n; i++) {
      final joined =
          (_state[i] & _upperMask) | (_state[(i + 1) % _n] & _lowerMask);
      var next = _state[(i + _m) % _n] ^ (joined >> 1);
      if (joined.isOdd) next ^= _matrixA;
      _state[i] = next & _mask32;
    }
    _index = 0;
  }

  /// One raw 32-bit draw.
  int nextUint32() {
    if (_index >= _n) _twist();
    var y = _state[_index++];
    y ^= y >> 11;
    y ^= (y << 7) & 0x9d2c5680;
    y ^= (y << 15) & 0xefc60000;
    y ^= y >> 18;
    return y & _mask32;
  }

  /// The top [bits] of a raw draw, as `getrandbits` returns them.
  ///
  /// Supports up to 32 bits, which is all this port's callers need.
  int nextBits(int bits) {
    if (bits < 0 || bits > 32) {
      throw ArgumentError.value(bits, 'bits', 'must be in 0..32');
    }
    if (bits == 0) return 0;
    return nextUint32() >> (32 - bits);
  }

  /// A uniform double in `[0, 1)`, built from two draws as `random()` is.
  double nextDouble() {
    final high = nextUint32() >> 5;
    final low = nextUint32() >> 6;
    return (high * 67108864.0 + low) * (1.0 / 9007199254740992.0);
  }

  /// A uniform integer in `[0, bound)`, drawn by rejection as `_randbelow` is.
  int nextIntBelow(int bound) {
    if (bound <= 0) {
      throw ArgumentError.value(bound, 'bound', 'must be positive');
    }
    final bits = bound.bitLength;
    var value = nextBits(bits);
    while (value >= bound) {
      value = nextBits(bits);
    }
    return value;
  }

  /// A uniformly chosen element of [items].
  ///
  /// Throws [ArgumentError] when [items] is empty.
  T choice<T>(List<T> items) {
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'must not be empty');
    }
    return items[nextIntBelow(items.length)];
  }

  /// A normal deviate, using the paired-value Box-Muller scheme `gauss` uses.
  ///
  /// Each polar pair yields two deviates and the second is cached, so the
  /// draw sequence only matches CPython when calls are interleaved the same
  /// way.
  double nextGaussian(double mu, double sigma) {
    var z = _pendingGaussian;
    _pendingGaussian = null;
    if (z == null) {
      final angle = nextDouble() * _twoPi;
      final radius = math.sqrt(-2.0 * math.log(1.0 - nextDouble()));
      z = math.cos(angle) * radius;
      _pendingGaussian = math.sin(angle) * radius;
    }
    return mu + z * sigma;
  }
}
