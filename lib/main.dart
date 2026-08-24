import 'package:material_ui/material_ui.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/practice/practice_screen.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(child: KeyRecallApp()));
}

class KeyRecallApp extends StatelessWidget {
  const KeyRecallApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'KeyRecall',
    theme: ThemeData(colorScheme: lightColorScheme),
    darkTheme: ThemeData(colorScheme: darkColorScheme),
    home: const PracticeScreen(),
  );
}
