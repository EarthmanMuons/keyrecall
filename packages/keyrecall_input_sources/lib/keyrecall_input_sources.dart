/// The shared Riverpod runtime every KeyRecall input source builds on.
///
/// Holds only what all sources need in common. Choosing which source is active
/// is the application's decision.
library;

export 'src/input_event_clock_provider.dart';
