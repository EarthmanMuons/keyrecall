import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'python_compatible_random.dart';
import 'synthetic_player.dart';

/// How much a hard moment slows the playing that arrives at it.
///
/// The exponent on the shortfall in local quality, so a moment the player is
/// comfortable with costs almost nothing and one they are not dwells for
/// several times as long. Provisional and uncalibrated: it is set so that a
/// player with a real opportunity penalty produces gaps the ordinary
/// continuity policy already calls a break, and device traces are what should
/// replace it.
const double _dwellPerShortfall = 2.5;

/// The most of the time a wrong note arrives when the material is supplied
/// throughout.
///
/// Continuous cues mean the notes are on the screen, so wrong ones come from
/// the hand rather than from not knowing the scale. The ceiling matches the
/// share of pitch integrity `SyntheticPlayer.play` leaves to motor quality
/// once the material is available.
const double _worstErrorRate = 0.15;

/// The least often a wrong note is followed by the right one.
///
/// A player who can hear the error fixes it, and the rest of the way to
/// certainty is local quality, so the moments that produce the most errors are
/// also the ones that leave the most of them standing.
const double _repairFloor = 0.4;

/// The most of the time an attempt is abandoned at a moment.
///
/// Squared against the shortfall, the way completion is in
/// `SyntheticPlayer.play`, so stopping is a consequence of an attempt going
/// badly rather than a tax on every attempt.
const double _worstStopRate = 0.2;

/// How long a repair takes, as a share of the player's ordinary interval.
const double _repairInterval = 0.4;

/// What [state] plays when handed [task].
///
/// The counterpart of `SyntheticPlayer.play` for the acquisition path, and a
/// different kind of answer. That one samples an outcome and reports scores
/// directly, so nothing it produces has a position. This produces a transcript
/// read through the same alignment and observation path device MIDI takes, so a
/// policy fed from here sees only what the instrument would have shown.
///
/// Positional structure comes from the exercise's own motor opportunity sites.
/// A crossing is a moment, so the player's [SyntheticPlayer.opportunityPenalty]
/// lands on that moment and nowhere else, and the hesitation, the wrong note,
/// or the stall that follows is an observation rather than a label. Nothing
/// downstream is told which moment was hard.
///
/// Four phenomena and no others: uneven but complete playing, a hesitation
/// localized to a moment, a wrong note with or without a repair, and stopping
/// partway. Each is what that failure looks like from the instrument rather
/// than a switch that selects it.
///
/// Nothing was asked about tempo, so the player plays at their own pace and
/// [SyntheticPlayer.tempoCompliance] never enters.
///
/// With [practising], the attempt updates the same latent ability as ordinary
/// work. The default observes the player without teaching them.
///
/// Throws [ArgumentError] for a two-hand parent. Two onset streams and the
/// distance between them are a coordination model, and acquisition has no
/// business having a second one.
PerformanceTranscript performAcquisition({
  required PlayerState state,
  required AcquisitionTask task,
  required PythonCompatibleRandom rng,
  bool practising = false,
}) {
  final conditions = task.parent.conditions;
  if (conditions.hands == HandConfiguration.together) {
    throw ArgumentError.value(
      conditions.hands.id,
      'task',
      'acquisition is offered below a single-hand floor',
    );
  }
  final hand = conditions.hands == HandConfiguration.left
      ? Hand.left
      : Hand.right;

  final material = task.material;
  final moments = realizeAcquisition(task).moments;
  final ordinaryIntervalMs = 60000 / state.naturalTempoFor(conditions.hands);

  var transcript = PerformanceTranscript.empty;
  var at = 0.0;
  var weakestQuality = 1.0;
  var allExpectedPlayed = true;

  PerformanceTranscript finish({required bool completed}) {
    if (practising && transcript.isNotEmpty) {
      state.practiseExecution(
        task.parent,
        weakestQuality,
        completed: completed,
      );
    }
    return transcript;
  }

  for (final moment in moments) {
    // Every draw a moment could need, taken before anything branches on them,
    // so the same task consumes the same stream whatever the playing does.
    final dwellZ = rng.nextGaussian(0, 1);
    final errorDraw = rng.nextDouble();
    final neighborDraw = rng.nextDouble();
    final repairDraw = rng.nextDouble();
    final stopDraw = rng.nextDouble();

    final effort = state.executionEffortFor(
      task.parent,
      momentIndex: moment.position,
    );
    final quality = _sigmoid(effort);
    final shortfall = 1 - quality;

    if (moment.position > 0) {
      if (stopDraw < _worstStopRate * shortfall * shortfall) {
        return finish(completed: false);
      }
      at +=
          ordinaryIntervalMs *
          math.exp(
            _dwellPerShortfall * shortfall + state.player.noise * dwellZ,
          );
    }

    weakestQuality = math.min(weakestQuality, quality);
    final expected = moment.noteFor(hand)!;
    if (errorDraw < _worstErrorRate * shortfall) {
      final wrong = expected.midiNote + (neighborDraw < 0.5 ? -1 : 1);
      transcript = transcript.appending(
        pitch: spellObservedPitch(wrong, material: material),
        timestampMs: at.round(),
      );
      if (repairDraw >= _repairFloor + (1 - _repairFloor) * quality) {
        allExpectedPlayed = false;
        continue;
      }
      at += ordinaryIntervalMs * _repairInterval;
    }

    transcript = transcript.appending(
      pitch: spellObservedPitch(expected.midiNote, material: material),
      timestampMs: at.round(),
    );
  }

  return finish(completed: allExpectedPlayed);
}

double _sigmoid(double value) => 1 / (1 + math.exp(-value));
