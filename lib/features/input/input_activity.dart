import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'input_temporal_events_provider.dart';

/// What the instrument is doing, as reconstructed from the event stream alone.
///
/// Nothing here reads the source's internal state. Tracking notes by replaying
/// note-ons, note-offs, pedal events, resets, and faults is exactly what any
/// consumer of live input has to do, so building the display this way keeps
/// the stream honest: if the events were not sufficient to know what is
/// sounding, this would visibly drift from the reducer's own snapshot.
///
/// The replay itself is [InputTemporalState], shared with everything else that
/// has to answer the same question. This adds only what a panel wants on top:
/// a scrollback and some counters.
@immutable
class InputActivity {
  /// What the stream says is sounding.
  final InputTemporalState observed;

  /// The most recent events, newest first, for watching the stream work.
  final List<String> recent;

  /// How many events have arrived since the stream opened.
  final int eventCount;

  /// How many resets have arrived.
  ///
  /// A reset mid-attempt means the observation is not continuous, which no
  /// scoring layer may measure across.
  final int resetCount;

  /// How many integrity faults have arrived.
  final int faultCount;

  const InputActivity({
    this.observed = InputTemporalState.silent,
    this.recent = const [],
    this.eventCount = 0,
    this.resetCount = 0,
    this.faultCount = 0,
  });

  /// Notes whose keys are believed to be held.
  Set<int> get pressedNoteNumbers => observed.pressedNoteNumbers;

  /// Notes released but believed to be ringing under the pedal.
  Set<int> get sustainedNoteNumbers => observed.sustainedNoteNumbers;

  /// Whether the pedal is believed to be down.
  bool get isPedalDown => observed.pedalDown;

  /// Every note believed to be making sound, however it is being held.
  Set<int> get soundingNoteNumbers => observed.soundingNoteNumbers;

  /// What ended the observation, if something did.
  InputIntegrityFault? get fault => observed.fault;

  /// Whether any input has arrived at all.
  bool get isIdle => eventCount == 0;

  /// This activity after [event].
  InputActivity applying(InputTemporalEvent event) => InputActivity(
    observed: observed.applying(event),
    recent: [
      '${event.timestampMs}ms  $event',
      ...recent.take(_recentEventLimit - 1),
    ],
    eventCount: eventCount + 1,
    resetCount: resetCount + (event is InputTemporalResetEvent ? 1 : 0),
    faultCount: faultCount + (event is InputTemporalFaultEvent ? 1 : 0),
  );
}

/// How many recent events the panel keeps. Enough to see a scale go by.
const int _recentEventLimit = 12;

/// Live input activity, whichever source is producing it.
final inputActivityProvider =
    NotifierProvider<InputActivityNotifier, InputActivity>(
      InputActivityNotifier.new,
    );

class InputActivityNotifier extends Notifier<InputActivity> {
  InputActivity _activity = const InputActivity();

  /// Whether [build] has returned, and so whether [state] can be assigned.
  ///
  /// A source with something to deliver already delivers it during the
  /// listen, before there is a state to read or replace.
  bool _isBuilt = false;

  @override
  InputActivity build() {
    _activity = const InputActivity();
    _isBuilt = false;
    // Listening here is also what keeps the selected source subscribed for as
    // long as anything is watching activity. Only data notifications: an
    // AsyncError retains the previous value, and counting that as another
    // event would report a note the instrument did not play twice.
    ref.listen<AsyncValue<InputTemporalEvent>>(inputTemporalEventsProvider, (
      _,
      next,
    ) {
      if (next case AsyncData(:final value)) _record(value);
    }, fireImmediately: true);
    _isBuilt = true;
    return _activity;
  }

  /// Applies [event] as though it had arrived, for tests that need a source
  /// failure the synthetic instrument cannot produce.
  @visibleForTesting
  void applyForTest(InputTemporalEvent event) => _record(event);

  void _record(InputTemporalEvent event) {
    _activity = _activity.applying(event);
    if (_isBuilt) state = _activity;
  }
}
