import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The on-device key/value store the app keeps its own settings in.
///
/// Must be overridden at startup with a real instance. Throwing rather than
/// defaulting is deliberate: a silent empty store reads as a first launch, so
/// a setting the learner chose would come back as the default instead of
/// failing where the wiring is wrong.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden at startup',
  );
});
