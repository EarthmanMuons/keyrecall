import 'dart:io';

/// [seeds] multiplied by `KEYRECALL_SEED_SCALE`, so a property checked on a
/// handful of seeds every commit can be searched widely on demand.
///
/// Throws [ArgumentError] unless the scale is a positive integer, since zero
/// would skip every seed and pass vacuously.
int seedBudget(int seeds) {
  final value = Platform.environment['KEYRECALL_SEED_SCALE'];
  if (value == null) return seeds;
  final scale = int.tryParse(value);
  if (scale == null || scale < 1) {
    throw ArgumentError.value(
      value,
      'KEYRECALL_SEED_SCALE',
      'must be a positive integer',
    );
  }
  return seeds * scale;
}
