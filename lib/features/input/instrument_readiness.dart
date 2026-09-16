import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
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

/// Whether the connected instrument's notes will carry performance timing.
enum TimingReadiness {
  /// The clock is still being identified, which the first notes settle.
  establishing,

  /// Notes are being timed.
  ready,

  /// The clock is one KeyRecall does not read playing from, for as long as
  /// this connection lasts.
  unavailable,

  /// The timeline lost continuity, and only a new observation restores it.
  failed,
}

/// Where timing stands for [phase], or null where there is nothing about
/// timing to say: no instrument is wanted, or none is being observed.
TimingReadiness? timingReadinessOf({
  required InputSourceKind source,
  required bool isObserving,
  required PerformanceClockPhase phase,
}) {
  if (!source.requiresInstrument || !isObserving) return null;
  return switch (phase) {
    PerformanceClockPhase.detecting => TimingReadiness.establishing,
    PerformanceClockPhase.active => TimingReadiness.ready,
    PerformanceClockPhase.unauthorized => TimingReadiness.unavailable,
    PerformanceClockPhase.failed => TimingReadiness.failed,
  };
}

/// Where the live instrument's timing stands before anything is played.
///
/// Read off the same mapper that times the notes, so what a learner is told
/// before an attempt is what the attempt will get.
final timingReadinessProvider = Provider<TimingReadiness?>((ref) {
  final source = ref.watch(inputSourceProvider);
  if (!source.requiresInstrument) return null;
  final input = ref.watch(midiInputProvider);
  return timingReadinessOf(
    source: source,
    isObserving: input.isObserving,
    phase: input.clockPhase,
  );
});
