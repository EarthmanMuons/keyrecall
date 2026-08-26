import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/practice/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Read before the first frame: which instrument was last connected decides
  // whether the app reconnects on its own, and a provider that discovers the
  // store later would have already answered that question with a guess.
  final preferences = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const KeyRecallApp(),
    ),
  );
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
