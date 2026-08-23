import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Access to the on-device key/value store.
///
/// Must be overridden at startup with a real instance:
///
/// ```dart
/// final preferences = await SharedPreferences.getInstance();
/// runApp(
///   ProviderScope(
///     overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
///     child: const KeyRecallApp(),
///   ),
/// );
/// ```
///
/// Throwing rather than defaulting is deliberate. A silent empty store would
/// look like a first launch, and the app would quietly forget which instrument
/// it was connected to instead of failing where the wiring is wrong.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden at startup',
  );
});
