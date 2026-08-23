import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

/// The monotonic clock every normalized input source timestamps against.
///
/// One per scope, shared by all sources. Two sources on two clocks could not
/// have their events ordered against each other, and a source swap would look
/// like time jumping.
///
/// It lives beside the MIDI transport only because that is the one source so
/// far. When a second arrives, this moves to wherever they both reach for it;
/// the vocabulary itself stays free of Riverpod.
final inputEventClockProvider = Provider<InputEventClock>((ref) {
  final clock = StopwatchInputClock();
  ref.onDispose(clock.stop);
  return clock.call;
});
