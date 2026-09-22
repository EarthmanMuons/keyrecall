import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/theme_mode.dart';

void main() {
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

  test('every mode has a name', () {
    for (final mode in ThemeMode.values) {
      expect(themeModeName(mode), isNotEmpty);
    }
  });
}
