/// Choosing where live input comes from, and presenting it as one stream.
///
/// The sources themselves live elsewhere: MIDI in `keyrecall_midi`, the
/// synthetic instrument in `features/demo_input`. Selecting between them is an
/// application decision, so it lives here rather than in either of them.
library;

export 'input_activity.dart';
export 'instrument_readiness.dart';
export 'midi_device_sheet.dart';
export 'input_source.dart';
export 'input_temporal_events_provider.dart';
