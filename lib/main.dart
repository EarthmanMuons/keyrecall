import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:material_ui/material_ui.dart';

import 'features/practice/home_screen.dart';
import 'theme.dart';

void main() {
  runApp(const ProviderScope(child: KeyRecallApp()));
}

class KeyRecallApp extends ConsumerWidget {
  const KeyRecallApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Instruments are reached over Bluetooth, which the OS may drop while the
    // app is backgrounded. Without this the app never learns it was away and
    // holds a stale connection on return.
    ref.watch(appMidiLifecycleProvider);

    return MaterialApp(
      title: 'KeyRecall',
      theme: ThemeData(colorScheme: lightColorScheme),
      darkTheme: ThemeData(colorScheme: darkColorScheme),
      home: const HomeScreen(),
    );
  }
}
