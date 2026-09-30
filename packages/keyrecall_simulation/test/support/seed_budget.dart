import 'dart:io';

/// [seeds] multiplied by `KEYRECALL_SEED_SCALE`, so a property checked on a
/// handful of seeds every commit can be searched widely on demand.
int seedBudget(int seeds) {
  final scale = Platform.environment['KEYRECALL_SEED_SCALE'];
  return scale == null ? seeds : seeds * int.parse(scale);
}
