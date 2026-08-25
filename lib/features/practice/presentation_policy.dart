import 'package:keyrecall_domain/keyrecall_domain.dart';

/// What V1 puts in front of a learner for a decided exercise.
///
/// The scheduler names a guidance rung; this turns it into the four
/// information channels an attempt is actually made under. Keeping the two
/// apart is what stops presentation choices from multiplying the candidate
/// space or riding along with a guidance change and making an attempt's
/// evidence unattributable.
///
/// V1 is deliberately uniform: a keyboard cue or none, never fingering, always
/// a neutral echo, always a count-in and no more. Only the pitch cue varies
/// with the rung, so a rung change moves one variable.
PresentationConditions presentationFor(GuidanceContext guidance) {
  final supplied = guidance.isMaterialSupplied;
  final presentation = PresentationConditions(
    pitchCue: supplied ? PitchCue.full : PitchCue.none,
    cueModality: supplied ? CueModality.keyboard : null,
    motorCue: MotorCue.none,
    performanceFeedback: PerformanceFeedback.neutralEcho,
    tempoSupport: TempoSupport.countInOnly,
  );
  // Not an assert: the rule has to hold in release builds too.
  if (!presentation.suitsGuidance(guidance)) {
    throw StateError(
      'presentation ${presentation.pitchCue.id} does not suit guidance '
      '${guidance.independence}',
    );
  }
  return presentation;
}

/// Whether the pitch cue is still on screen once the attempt has started.
///
/// The rung owns this, not the cue: [GuidanceContext.notesPreviewedOnly]
/// supplies the same material as [GuidanceContext.continuouslyCued] and takes
/// it away at Ready. Bringing it back on request would silently be the cued
/// rung.
bool showsPitchCueDuringAttempt(GuidanceContext guidance) =>
    guidance.concurrentPitchCues;
