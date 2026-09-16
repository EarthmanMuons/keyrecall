import 'package:keyrecall_input/keyrecall_input.dart';

import '../input/input.dart';

/// Why an attempt carries no timing, as far as its own notes can say.
///
/// Attempt-local on purpose. A connection that times perfectly well still
/// produces an attempt too short to read, and blaming the connection for that
/// sends the learner to fix something that is not broken.
enum TimingShortfall {
  /// The source does not stamp its notes at all.
  unsupportedSource,

  /// The instrument's clock had not been identified yet.
  identifyingClock,

  /// The instrument's clock is one KeyRecall does not read playing from.
  unsupportedClock,

  /// The instrument's timeline lost continuity and stays lost until the
  /// observation restarts.
  timelineFailed,

  /// The instrument sent notes without timestamps.
  missingTimestamps,

  /// Every note was timed and there were too few of them.
  insufficientObservations,
}

/// The shortfall behind an attempt whose most recent untimed note was untimed
/// because of [lastUntimed], or which had none.
///
/// The most recent rather than the first, because a timeline that failed
/// partway through an attempt is what left the rest of it untimed.
TimingShortfall timingShortfallFor(
  TimingUnavailableReason? lastUntimed, {
  required InputSourceKind source,
}) {
  if (!source.requiresInstrument) return TimingShortfall.unsupportedSource;
  return switch (lastUntimed) {
    null => TimingShortfall.insufficientObservations,
    TimingUnavailableReason.detecting => TimingShortfall.identifyingClock,
    TimingUnavailableReason.nonPerformanceDomain ||
    TimingUnavailableReason.unknownDomain => TimingShortfall.unsupportedClock,
    TimingUnavailableReason.missingTransportTimestamp =>
      TimingShortfall.missingTimestamps,
    TimingUnavailableReason.ambiguousWrap ||
    TimingUnavailableReason.implausibleClockStep ||
    TimingUnavailableReason.continuityLost => TimingShortfall.timelineFailed,
  };
}

/// What to tell a learner about [shortfall], or about an attempt whose cause
/// nothing kept when it is null.
String timingShortfallSentence(TimingShortfall? shortfall) =>
    switch (shortfall) {
      null => 'Timing could not be read for this attempt.',
      TimingShortfall.unsupportedSource =>
        'The on-screen keyboard does not report timing.',
      TimingShortfall.identifyingClock =>
        "Timing was unavailable while KeyRecall identified your piano's "
            'clock.',
      TimingShortfall.unsupportedClock =>
        'Timing is unavailable because this connection stamps notes with a '
            'clock KeyRecall cannot time playing from.',
      TimingShortfall.timelineFailed =>
        "Timing stopped when your piano's clock lost its place. Reconnecting "
            'your piano starts it again.',
      TimingShortfall.missingTimestamps =>
        'Timing is unavailable because your piano sent notes without '
            'timestamps.',
      TimingShortfall.insufficientObservations =>
        'Too short to read timing from.',
    };
