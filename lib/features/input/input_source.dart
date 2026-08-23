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
/// Starts on the synthetic one, so a launch with nothing plugged in still
/// reaches a working practice loop. Connecting an instrument is what moves it,
/// and that is an explicit decision rather than something inferred from a
/// device appearing: a keyboard powering up nearby should not silently take
/// over an attempt in progress.
final inputSourceProvider =
    NotifierProvider<InputSourceNotifier, InputSourceKind>(
      InputSourceNotifier.new,
    );

class InputSourceNotifier extends Notifier<InputSourceKind> {
  @override
  InputSourceKind build() => InputSourceKind.demo;

  /// Switches to [kind].
  void use(InputSourceKind kind) => state = kind;

  /// Switches between the synthetic instrument and a real one.
  void toggle() => state = switch (state) {
    InputSourceKind.demo => InputSourceKind.midi,
    InputSourceKind.midi => InputSourceKind.demo,
  };
}
