import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:flutter/foundation.dart';

/// Which evidence channel an attempt's fault came from.
///
/// The observation model keeps these apart all the way down, and the point of
/// naming one is that they are different problems with different answers.
/// Playing the wrong notes is not the same as playing the right ones raggedly,
/// and neither is the same as two hands that each played correctly and did not
/// arrive together.
enum AttemptFault {
  /// A pitch was wrong, or a note nothing asked for arrived.
  notes,

  /// The playing stopped and started.
  continuity,

  /// The playing never settled into a pulse.
  steadiness,

  /// The hands came apart.
  coordination,
}

/// A place in the traversal, coarse enough that naming it is always true.
///
/// Positions are exact and useless to say out loud: nobody knows where the
/// eleventh moment was. These are the landmarks a player already has words
/// for, and there are no others, so a fault is either at one of them or
/// unlocated.
enum TraversalLandmark {
  start('at the start'),
  ascent('on the way up'),
  turn('at the turn'),
  descent('on the way down'),
  end('at the end');

  const TraversalLandmark(this.phrase);

  /// How to say it in a sentence.
  final String phrase;
}

/// What happened on one attempt, as one sentence.
///
/// Three questions, and no more: did it finish, what went wrong, and where.
/// Everything the observation model saw is already in the journal, so this is
/// free to say the one true thing that helps rather than the fifteen that are
/// also true. A learner mid-sitting is deciding whether to keep going.
///
/// Nothing here is softened and nothing is invented. An attempt that fell
/// apart says so, an attempt that went well says so, and an attempt nobody can
/// locate a fault in gets no location.
@immutable
class AttemptDiagnosis {
  /// Whether anything arrived at all.
  final bool started;

  /// Whether every note that was asked for eventually arrived.
  final bool finished;

  /// The channel the attempt fell down in, or null when none did.
  final AttemptFault? fault;

  /// Where the fault showed, or null when nothing locates it.
  final TraversalLandmark? where;

  /// Whether the learner reported that the material would not come.
  final bool declined;

  /// Whether the exercise asked for both hands.
  final bool handsTogether;

  /// Expected notes something else was played for, or null when nothing
  /// counted them.
  final int? slippedNotes;

  /// Notes that arrived without being asked for, or null when nothing counted
  /// them.
  final int? extraNotes;

  const AttemptDiagnosis({
    required this.started,
    required this.finished,
    required this.fault,
    required this.where,
    required this.declined,
    required this.handsTogether,
    this.slippedNotes,
    this.extraNotes,
  });

  /// The sentence to put on the screen.
  String get sentence {
    if (declined) return 'Noted. That one would not come.';
    if (!started) return 'Nothing came through.';
    if (!finished) {
      return where == null
          ? 'That one did not get all the way through.'
          : 'It ran out ${where!.phrase}.';
    }

    return switch (fault) {
      null =>
        handsTogether
            ? 'Clean pass, hands together the whole way.'
            : 'Clean pass, steady the whole way.',
      AttemptFault.notes => _notesSentence,
      AttemptFault.continuity =>
        'The notes were right; the pause$_where broke it up.',
      AttemptFault.steadiness =>
        'The notes were right; the pulse kept moving around.',
      AttemptFault.coordination =>
        'Both hands had the notes, but they came apart$_where.',
    };
  }

  /// What went wrong with the notes, counted rather than characterized.
  ///
  /// "A few" is a guess, and it is the wrong guess exactly when the attempt
  /// went worst. The edit script knows how many, so this says how many, and
  /// falls back to the vague version only when there is no script to ask.
  ///
  /// A wrong note and an extra note are different things and are named
  /// differently, but only while the attempt made one kind of mistake. An
  /// attempt that made both is totalled instead: naming one kind would hide
  /// the other, and naming both is the changelog this is meant not to be.
  String get _notesSentence {
    final slipped = slippedNotes;
    final extra = extraNotes;
    if (slipped == null || extra == null) {
      return 'A few pitches slipped$_where.';
    }
    if (slipped > 0 && extra > 0) return '${slipped + extra} notes went wrong.';
    if (slipped == 1) return 'A pitch slipped$_where.';
    if (slipped > 1) return '$slipped pitches slipped$_where.';
    return extra == 1
        ? 'An extra note crept in$_where.'
        : '$extra extra notes crept in.';
  }

  String get _where => where == null ? '' : ' ${where!.phrase}';

  @override
  String toString() =>
      'AttemptDiagnosis(finished: $finished, ${fault?.name ?? 'clean'})';
}

/// What to say about the attempt [closure] recorded, or null when nothing was
/// measured.
///
/// [reading] is the correspondence the closure was made from, which nothing
/// persists. Without it the channel is still known and the place is not, so a
/// replayed attempt diagnoses correctly and says less.
AttemptDiagnosis? diagnose({
  required Exercise exercise,
  required AttemptClosure closure,
  PerformanceReading? reading,
}) {
  if (closure.measurement case Measured(:final outcome)) {
    final script = reading?.measurement.reading;
    final fault = _faultIn(outcome);
    return AttemptDiagnosis(
      started: outcome.started,
      finished: outcome.completed,
      fault: fault,
      where: _locate(
        outcome.completed ? fault : null,
        exercise: exercise,
        reading: reading,
      ),
      declined: closure.termination == AttemptTermination.learnerDeclined,
      handsTogether: exercise.conditions.hands == HandConfiguration.together,
      slippedNotes: script?.substituted,
      extraNotes: script?.inserted,
    );
  }
  return null;
}

/// The one channel worth naming, or null when none of them is.
///
/// Each channel has its own boundary and none of them was invented here. The
/// timing and coordination scores reach exactly `1` for playing the
/// measurement policy calls comfortable, which is where its instrument takes
/// put it, so falling short of one is already the calibrated statement that
/// something was outside ordinary playing. Pitch integrity reaches `1` when
/// every note that sounded was the note asked for, which needs no threshold at
/// all.
///
/// The order is a judgment about what helps, not about what is worst. The
/// pitches are the substance of the task, so a wrong note is named ahead of how
/// it sat in time. Hands that came apart are named next, because a
/// hands-together exercise exists to put them together and nothing else on the
/// screen would say so. A break is named ahead of unevenness because stopping
/// is the more concrete thing to have happened.
AttemptFault? _faultIn(Outcome outcome) {
  if (outcome.pitchIntegrity < 1) return AttemptFault.notes;
  if ((outcome.coordination ?? 1) < 1) return AttemptFault.coordination;
  if (outcome.continuity < 1) return AttemptFault.continuity;
  if (outcome.temporalStability < 1) return AttemptFault.steadiness;
  return null;
}

/// Where [fault] showed, or null when the reading cannot say.
///
/// An unfinished attempt is located by where it ran out instead, which is why
/// the caller passes no fault for one: the interesting place is the end of the
/// playing, not the first thing that went wrong inside it.
TraversalLandmark? _locate(
  AttemptFault? fault, {
  required Exercise exercise,
  required PerformanceReading? reading,
}) {
  if (reading == null) return null;
  final measurement = reading.measurement;
  final script = measurement.reading;

  final position = switch (fault) {
    null => script.firstAbsentPosition,
    // Only one wrong note has a place. Naming where the first of several
    // happened would read as a claim about all of them, and the rest may have
    // been somewhere else entirely.
    AttemptFault.notes =>
      script.substituted + script.inserted != 1
          ? null
          : switch (script.firstDeparture) {
              AtExpectedPosition(:final position) => position,
              BeforeExpectedPosition(:final position) => position,
              AfterRealization() => measurement.expectedMoments - 1,
              null => null,
            },
    AttemptFault.continuity => measurement.longestGapBeforePosition,
    AttemptFault.coordination => measurement.widestAsynchronyAtPosition,
    // Spread is a property of the whole traversal and happened nowhere in
    // particular. Pointing at its worst interval would name a moment that was
    // no different from the others.
    AttemptFault.steadiness => null,
  };

  return position == null ? null : landmarkAt(position, realize(exercise));
}

/// Which landmark of [realization] the moment at [position] belongs to.
///
/// The turn absorbs the moment on either side of the apex, because a hand
/// changing direction is not an instant and nobody perceives the note before
/// the top as being somewhere else. A traversal that only ascends has no
/// interior apex, so it never reports a turn or a descent.
TraversalLandmark landmarkAt(int position, ExerciseRealization realization) {
  final last = realization.moments.length - 1;
  if (position <= 0) return TraversalLandmark.start;
  if (position >= last) return TraversalLandmark.end;

  final apex = _apexOf(realization);
  if (apex > 0 && apex < last && (position - apex).abs() <= 1) {
    return TraversalLandmark.turn;
  }
  return position < apex ? TraversalLandmark.ascent : TraversalLandmark.descent;
}

/// The first moment holding the highest note of the traversal.
int _apexOf(ExerciseRealization realization) {
  var apex = 0;
  var highest = 0;
  for (final moment in realization.moments) {
    final top = moment.notes
        .map((note) => note.midiNote)
        .reduce((a, b) => a > b ? a : b);
    if (top > highest) {
      highest = top;
      apex = moment.position;
    }
  }
  return apex;
}
