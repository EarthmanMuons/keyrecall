/// The shared runtime every KeyRecall input source builds on.
///
/// `keyrecall_input` defines the vocabulary and stays pure Dart. This package
/// is the thin Riverpod layer underneath the sources that produce it, holding
/// only what all of them need in common.
///
/// Which source is active, and how one is chosen, is the application's
/// decision and lives there. Nothing here knows that MIDI or a synthetic
/// source exist.
library;

export 'src/input_event_clock_provider.dart';
