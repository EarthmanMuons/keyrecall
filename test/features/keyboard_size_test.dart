import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keyrecall/features/piano/piano.dart';
import 'package:keyrecall/features/practice/keyboard_size.dart';
import 'package:keyrecall/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, SharedPreferences)> containerWith(
    Map<String, Object> stored,
  ) async {
    SharedPreferences.setMockInitialValues(stored);
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    return (container, preferences);
  }

  test('a profile that has never resized gets the default', () async {
    final (container, _) = await containerWith(const {});

    expect(container.read(keyboardSizeProvider('a')).isDefault, isTrue);
  });

  test('each profile keeps its own size', () async {
    final (container, _) = await containerWith(const {});

    await container.read(keyboardSizeProvider('a').notifier).setWidthScale(2);
    await container
        .read(keyboardSizeProvider('b').notifier)
        .setHeightScale(1.5);

    expect(container.read(keyboardSizeProvider('a')).widthScale, 2);
    expect(container.read(keyboardSizeProvider('a')).heightScale, 1);
    expect(container.read(keyboardSizeProvider('b')).widthScale, 1);
    expect(container.read(keyboardSizeProvider('b')).heightScale, 1.5);
  });

  test('a stored size is what the profile opens with', () async {
    final (first, preferences) = await containerWith(const {});
    await first.read(keyboardSizeProvider('a').notifier).setWidthScale(1.5);

    final reopened = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(reopened.dispose);

    expect(reopened.read(keyboardSizeProvider('a')).widthScale, 1.5);
  });

  test('a size outside the range is clamped into it', () async {
    final (container, _) = await containerWith(const {});

    await container.read(keyboardSizeProvider('a').notifier).setWidthScale(9);

    expect(
      container.read(keyboardSizeProvider('a')).widthScale,
      PianoViewSettings.maxScale,
    );
  });

  test('a deleted profile leaves nothing behind', () async {
    final (container, preferences) = await containerWith(const {});
    await container.read(keyboardSizeProvider('a').notifier).setWidthScale(2);
    await container.read(keyboardSizeProvider('b').notifier).setWidthScale(2);

    await forgetKeyboardSize(preferences, 'a');

    expect(preferences.getKeys().where((key) => key.contains('.a.')), isEmpty);
    expect(
      preferences.getKeys().where((key) => key.contains('.b.')),
      isNotEmpty,
    );
  });
}
