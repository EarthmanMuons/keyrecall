import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../preferences.dart';
import '../piano/piano.dart';

/// How large one profile has asked for the keyboard to be.
///
/// Kept per profile rather than per device: the device decides the default,
/// and how far past it the keys and the keyboard are grown is a preference of
/// the person practicing. Stored as asked for, so a window with less room
/// clamps it without overwriting it.
final keyboardSizeProvider =
    NotifierProvider.family<KeyboardSizeNotifier, PianoViewSettings, String>(
      KeyboardSizeNotifier.new,
    );

class KeyboardSizeNotifier extends Notifier<PianoViewSettings> {
  KeyboardSizeNotifier(this.profileId);

  final String profileId;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  PianoViewSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return PianoViewSettings(
      widthScale: PianoViewSettings.clampScale(
        prefs.getDouble(_widthKey(profileId)) ?? 1.0,
      ),
      heightScale: PianoViewSettings.clampScale(
        prefs.getDouble(_heightKey(profileId)) ?? 1.0,
      ),
    );
  }

  Future<void> setWidthScale(double widthScale) async {
    final clamped = PianoViewSettings.clampScale(widthScale);
    state = state.copyWith(widthScale: clamped);
    await _prefs.setDouble(_widthKey(profileId), clamped);
  }

  Future<void> setHeightScale(double heightScale) async {
    final clamped = PianoViewSettings.clampScale(heightScale);
    state = state.copyWith(heightScale: clamped);
    await _prefs.setDouble(_heightKey(profileId), clamped);
  }

  Future<void> reset() async {
    state = const PianoViewSettings.defaults();
    await forgetKeyboardSize(_prefs, profileId);
  }
}

/// Drops what [profileId] asked for, for a profile that is going away.
Future<void> forgetKeyboardSize(SharedPreferences prefs, String profileId) =>
    Future.wait([
      prefs.remove(_widthKey(profileId)),
      prefs.remove(_heightKey(profileId)),
    ]);

String _widthKey(String profileId) => 'app.keyboard.$profileId.widthScale';
String _heightKey(String profileId) => 'app.keyboard.$profileId.heightScale';
