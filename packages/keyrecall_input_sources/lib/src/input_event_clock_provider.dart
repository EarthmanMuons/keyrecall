import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

/// The monotonic clock every normalized input source timestamps against.
///
/// One per scope, shared by all sources so their events can be ordered against
/// each other. A shared timeline is not a shared performance: each source opens
/// with a reset, and that reset is a hard measurement boundary.
final inputEventClockProvider = Provider<InputEventClock>((ref) {
  final clock = StopwatchInputClock();
  ref.onDispose(clock.stop);
  return clock.call;
});
