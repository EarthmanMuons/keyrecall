/// The normalized live-input vocabulary for KeyRecall.
///
/// Every input source reduces to [InputTemporalEvent], so nothing downstream
/// reasons about transports.
library;

export 'src/input_event_clock.dart';
export 'src/input_note_event.dart';
export 'src/input_temporal_event.dart';
