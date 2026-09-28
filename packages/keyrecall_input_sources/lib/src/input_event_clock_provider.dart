import 'package:clock/clock.dart' as system;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

/// The monotonic clock every normalized input source timestamps against.
///
/// One per scope, shared by all sources so their events can be ordered against
/// each other. A shared timeline is not a shared performance: each source opens
/// with a reset, and that reset is a hard measurement boundary.
///
/// Read from `package:clock`, the system clock in the app and the pumped one
/// under a widget test, the way `PulseSchedule` is. An attempt's downbeat is
/// placed on this timeline, so the two have to agree about how time passes.
final inputEventClockProvider = Provider<InputEventClock>((ref) {
  final clock = StopwatchInputClock(system.clock.stopwatch());
  ref.onDispose(clock.stop);
  return clock.call;
});
