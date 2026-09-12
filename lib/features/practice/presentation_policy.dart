import 'package:keyrecall_domain/keyrecall_domain.dart';

/// What V1 puts in front of a learner for a decided exercise.
///
/// The scheduler names a guidance rung and this turns it into the four
/// information channels an attempt is made under. Keeping the two apart is what
/// stops a presentation choice from multiplying the candidate space or riding
/// along with a guidance change and making an attempt's evidence
/// unattributable.
///
/// V1 is uniform: a cue on both the keyboard and the staff or no cue at all,
/// always a neutral echo, always a count-in and no more. Only the pitch cue
/// varies with the rung, so a rung change moves one variable. Fingering varies
/// with the material, shown wherever the catalog has one that is not a guess.
///
/// A supplied cue is written in both modalities because they answer different
/// questions: the keyboard says which key and names a finger, the staff says
/// which note in the notation a learner meets elsewhere. The unguided rung
/// shows neither.
PresentationConditions presentationFor(
  GuidanceContext guidance, {
  Exercise? exercise,
}) {
  final supplied = guidance.isMaterialSupplied;
  // Fingering is execution support and rides with the cue: naming the finger
  // for a note the learner is trying to recall would supply half the answer.
  final fingered =
      supplied &&
      exercise != null &&
      realize(exercise).hands
          .every((hand) => fingeringFor(exercise, hand) != null);
  final presentation = PresentationConditions(
    pitchCue: supplied ? PitchCue.full : PitchCue.none,
    cueModality: supplied ? CueModality.keyboardAndStaff : null,
    motorCue: fingered ? MotorCue.fingering : MotorCue.none,
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

/// Whether a cue in [modality] is written on a staff.
bool cueOnStaff(CueModality? modality) =>
    modality == CueModality.staff || modality == CueModality.keyboardAndStaff;

/// Whether a cue in [modality] marks the keyboard diagram.
bool cueOnKeyboard(CueModality? modality) =>
    modality == CueModality.keyboard ||
    modality == CueModality.keyboardAndStaff;
