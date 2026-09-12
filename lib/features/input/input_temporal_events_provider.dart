import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

import '../demo_input/demo_input.dart';
import 'input_source.dart';

/// Live input, whatever is producing it.
///
/// The only input the practice loop sees. The scheduler, the learner model, and
/// the attempt journal are written against the normalized vocabulary and cannot
/// tell whether a person played the notes or the synthetic instrument did.
///
/// Both sources share one clock, so a swap mid-session continues the same
/// timeline instead of restarting it. Each source opens with a reset carrying
/// what was sounding, which tells a consumer the observation is not continuous
/// across the boundary.
final inputTemporalEventsProvider = StreamProvider<InputTemporalEvent>((ref) {
  final source = ref.watch(inputSourceProvider);
  return ref.watch(switch (source) {
    InputSourceKind.demo => demoTemporalEventsProvider,
    InputSourceKind.midi => midiTemporalEventsProvider,
  });
});
