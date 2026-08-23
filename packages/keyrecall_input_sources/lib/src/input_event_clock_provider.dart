import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

/// The monotonic clock every normalized input source timestamps against.
///
/// One per scope, shared by all of them. Two sources on two clocks could not
/// have their events ordered against each other, and switching sources would
/// look like time jumping rather than like one continuous input session.
///
/// A shared timeline is not a shared performance. Each source opens with a
/// reset, and that reset is a hard boundary: what came before it cannot be
/// measured against what comes after, however comparable the timestamps look.
///
/// This sits below every source rather than inside one, which is the only
/// reason this package exists: a synthetic source has no business depending on
/// the MIDI package to find out what time it is.
final inputEventClockProvider = Provider<InputEventClock>((ref) {
  final clock = StopwatchInputClock();
  ref.onDispose(clock.stop);
  return clock.call;
});
