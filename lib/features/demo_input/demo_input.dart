/// A synthetic instrument, so the practice loop runs with nothing plugged in.
///
/// It plays what it is told and produces the same normalized event stream a
/// real keyboard does. Nothing downstream can tell which one it is talking to,
/// which is the whole point: the scheduler, the learner model, and the attempt
/// journal can all be exercised end to end before any hardware exists.
///
/// The instrument knows nothing about scales, exercises, or whether what it
/// played was correct, and holds no authored sequence. Deciding those is the
/// practice loop's job, and an instrument that knew them would be simulating
/// the answer rather than the playing. Anything that scripts a tour belongs in
/// a layer above this one, telling the instrument what to play.
library;

export 'cancelable_timer_sequence.dart';
export 'demo_input_notifier.dart';
export 'demo_temporal_events_provider.dart';
