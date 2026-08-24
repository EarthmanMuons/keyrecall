import 'package:keyrecall_domain/keyrecall_domain.dart';

/// How V1 shows a decided exercise.
///
/// The practice policy owns this choice, not the scheduler: the scheduler
/// decides material, conditions, and guidance rung, and this decides how that
/// rung is rendered. Keeping the two apart is what stops representation and
/// tempo support from multiplying the candidate space or riding along with a
/// guidance change and making an attempt's evidence unattributable.
///
/// V1 is deliberately uniform. Every attempt gets a count-in and nothing more,
/// so the only thing that varies with the rung is whether the pitch material
/// is on screen and for how long. A continuous metronome is real practice
/// support and would change execution demand, so it stays an explicit feature
/// rather than something a rung quietly turns on.
PresentationConditions presentationFor(GuidanceContext guidance) {
  final presentation = PresentationConditions(
    pitchRepresentation: guidance.isMaterialSupplied
        ? PitchRepresentation.keyboard
        : PitchRepresentation.none,
    tempoSupport: TempoSupport.countInOnly,
  );
  // Not an assert: the rule has to hold in release builds too.
  if (!presentation.suitsGuidance(guidance)) {
    throw StateError(
      'presentation ${presentation.pitchRepresentation.id} does not suit '
      'guidance ${guidance.independence}',
    );
  }
  return presentation;
}

/// Whether the pitch material stays on screen once the attempt has started.
///
/// True only when the material is supplied throughout. At
/// [GuidanceContext.notesPreviewedOnly] the surface is shown until the learner
/// says they are ready and never comes back: bringing it back on request would
/// silently be the cued rung.
bool showsPitchDuringAttempt(GuidanceContext guidance) =>
    guidance.concurrentPitchCues;

/// Whether played notes light up on the diagram during the attempt.
///
/// A live highlight is pitch-bearing, and it also reveals errors as they
/// happen, so it belongs to the pitch axis rather than to input plumbing.
/// Wiring MIDI straight to the diagram would put a cue back on screen at the
/// rungs that exist to remove it. Only the continuously cued rung, which is
/// already the supported-practice condition, gets it.
bool showsLiveKeysDuringAttempt(GuidanceContext guidance) =>
    guidance.concurrentPitchCues;
