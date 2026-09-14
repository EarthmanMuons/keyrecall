import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

import '../demo_input/demo_input.dart';

/// Where live input is coming from.
enum InputSourceKind {
  /// A synthetic instrument, playing what the app tells it to.
  demo,

  /// A real instrument, over MIDI.
  midi;

  /// Whether this source needs hardware to be attached.
  bool get requiresInstrument => this == InputSourceKind.midi;
}

/// Which input source is active.
///
/// Starts on MIDI, because practice happens at an instrument. The synthetic
/// source is driven from tests and simulations, which select it explicitly.
final inputSourceProvider =
    NotifierProvider<InputSourceNotifier, InputSourceKind>(
      InputSourceNotifier.new,
    );

class InputSourceNotifier extends Notifier<InputSourceKind> {
  @override
  InputSourceKind build() => InputSourceKind.midi;

  /// Switches to [kind].
  void use(InputSourceKind kind) => state = kind;

  /// Switches between the synthetic instrument and a real one.
  void toggle() => state = switch (state) {
    InputSourceKind.demo => InputSourceKind.midi,
    InputSourceKind.midi => InputSourceKind.demo,
  };
}

/// What the selected source says it is holding right now.
///
/// The source's own snapshot rather than a replay of its events, for a
/// consumer that attaches partway through and has no history to replay. Every
/// source keeps one because the reducer keeps one, and a consumer that started
/// late would otherwise take the last event it happened to catch for the whole
/// state.
final inputSnapshotProvider = Provider<InputTemporalSnapshot>((ref) {
  final source = ref.watch(inputSourceProvider);
  switch (source) {
    case InputSourceKind.demo:
      final demo = ref.watch(demoInputProvider);
      return InputTemporalSnapshot(
        pressedNoteNumbers: demo.pressedNoteNumbers,
        sustainedNoteNumbers: demo.sustainedNoteNumbers,
        pedalDown: demo.isPedalDown,
      );
    case InputSourceKind.midi:
      return ref.watch(midiInputProvider).snapshot;
  }
});

/// Whether the selected source is observing, and which observation it is on.
///
/// The source's own lifecycle state rather than a reading of its events. A
/// consumer that attaches partway through is handed whatever event the shared
/// stream last delivered, which may be a note rather than the opening reset,
/// and a note is not a lifecycle fact.
typedef InputObservationState = ({
  bool isLive,
  String? observationId,
  InputIntegrityFault? fault,
});

/// Where the selected source's observation stands right now.
final inputObservationProvider = Provider<InputObservationState>((ref) {
  final source = ref.watch(inputSourceProvider);
  switch (source) {
    case InputSourceKind.demo:
      // The synthetic instrument observes for as long as its stream exists,
      // and the stream opens one when it is built.
      return (isLive: true, observationId: 'demo', fault: null);
    case InputSourceKind.midi:
      final input = ref.watch(midiInputProvider);
      return (
        isLive: input.isObserving,
        observationId: input.adopted?.sessionId,
        fault: input.fault,
      );
  }
});

/// What the adopted instrument's clock is authorized to say about playing.
///
/// The policy's reading of what the mapper measured, for a surface that has to
/// explain why timing is or is not available on this connection.
final clockAuthorizationProvider = Provider<ClockAuthorization>(
  (ref) => ClockDomainPolicy.characterized.classify(
    ref.watch(midiInputProvider).clockObservation,
  ),
);
