import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The on-device key/value store this package keeps its preferences in.
///
/// Must be overridden at startup with a real instance:
///
/// ```dart
/// final preferences = await SharedPreferences.getInstance();
/// runApp(
///   ProviderScope(
///     overrides: [midiPreferenceStoreProvider.overrideWithValue(preferences)],
///     child: const KeyRecallApp(),
///   ),
/// );
/// ```
///
/// A store of its own, rather than a reach into the host app's, so nothing
/// outside MIDI has to depend on this package to find its own settings.
///
/// Throwing rather than defaulting is deliberate. A silent empty store would
/// look like a first launch, and the app would quietly forget which instrument
/// it was connected to instead of failing where the wiring is wrong.
final midiPreferenceStoreProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'midiPreferenceStoreProvider must be overridden at startup',
  );
});
