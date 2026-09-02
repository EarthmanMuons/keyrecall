import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

import 'input_source.dart';

/// What the app can say about the instrument when nothing was played.
enum InstrumentReadiness {
  /// Nothing has to be attached, so silence is not the instrument's doing.
  notNeeded,

  /// No instrument is connected, which is the likely reason nothing arrived.
  disconnected,

  /// An instrument is connected, so silence is something else.
  connected,
}

/// Whether an instrument is attached.
///
/// The connection state is only read where an instrument is wanted: reading it
/// starts the Bluetooth stack, which the synthetic source has no use for.
final instrumentReadinessProvider = Provider<InstrumentReadiness>((ref) {
  if (!ref.watch(inputSourceProvider).requiresInstrument) {
    return InstrumentReadiness.notNeeded;
  }
  return ref.watch(midiConnectionStateProvider).isConnected
      ? InstrumentReadiness.connected
      : InstrumentReadiness.disconnected;
});
