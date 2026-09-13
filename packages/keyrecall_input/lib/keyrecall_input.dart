/// The normalized live-input vocabulary for KeyRecall.
///
/// Every input source reduces to [InputTemporalEvent] through [InputReducer],
/// so nothing downstream reasons about transports, and no two consumers can
/// hold different beliefs about what is sounding.
library;

export 'src/clock_domain.dart';
export 'src/input_event_clock.dart';
export 'src/input_integrity.dart';
export 'src/input_note_event.dart';
export 'src/input_reducer.dart';
export 'src/input_temporal_event.dart';
export 'src/input_temporal_state.dart';
export 'src/performance_timing.dart';
export 'src/raw_input_envelope.dart';
