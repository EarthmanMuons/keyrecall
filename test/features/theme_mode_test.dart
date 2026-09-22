import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keyrecall/theme_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('cycling reaches every mode and returns to the start', () {
    var mode = ThemeMode.system;
    final visited = <ThemeMode>[];
    for (var step = 0; step < ThemeMode.values.length; step++) {
      mode = nextThemeMode(mode);
      visited.add(mode);
    }

    expect(visited.toSet(), ThemeMode.values.toSet());
    expect(mode, ThemeMode.system);
  });

  test('an install that has never chosen follows the system', () async {
    final container = await containerWith(const {});

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('a stored choice is what the app opens with', () async {
    final container = await containerWith(const {'app.themeMode': 'dark'});

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('a value the app cannot read falls back to the system', () async {
    final container = await containerWith(const {'app.themeMode': 'sepia'});

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('choosing a mode takes effect and survives the next launch', () async {
    final container = await containerWith(const {});

    await container.read(themeModeProvider.notifier).set(ThemeMode.light);

    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(
      (await SharedPreferences.getInstance()).getString('app.themeMode'),
      'light',
    );
  });
}
