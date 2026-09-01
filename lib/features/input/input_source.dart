import 'package:flutter_riverpod/flutter_riverpod.dart';

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
