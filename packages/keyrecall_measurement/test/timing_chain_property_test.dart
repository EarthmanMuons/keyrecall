import 'dart:math' as math;

import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_testing/keyrecall_testing.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

final List<TechnicalMaterial> materials = [
  ...allScales,
  ...allRootPositionArpeggios,
];

final Arbitrary<Exercise> anyExercise =
    combine6(
      choiceOf(materials),
      choiceOf(HandConfiguration.values),
      choiceOf([1, 2]),
      choiceOf(ExerciseDirection.values),
      choiceOf(HandMotion.values),
      choiceOf([40.0, 60.0, 90.0, 120.0, 160.0]),
    ).map((parts) {
      final (material, hands, octaves, direction, motion, tempo) = parts;
      return Exercise.linear(
        material: material,
        hands: hands,
        octaves: octaves,
        direction: direction,
        handMotion: hands == HandConfiguration.together
            ? motion
            : HandMotion.parallel,
        tempoBpm: tempo,
      );
    });

/// One way the pitches depart from what was asked: a note dropped, one added,
/// one played an octave away, or one played as another key.
typedef Slip = (int, double, int);

final Arbitrary<Slip> anySlip = combine3(
  integer(min: 0, max: 3),
  float(min: 0, max: 1),
  integer(min: 21, max: 108),
);

/// Where performance times are missing.
enum Untimed { none, all, first, last, interior, oneHand }

/// How the playing sat on the instrument's clock: the usual wait between
/// moments, how far it drifts by the end, per-note jitter, pauses, whether
/// every moment lands at once, how far the right hand sits from the left, and
/// which notes carry no time at all.
typedef Playing = (
  int,
  double,
  int,
  List<(double, int)>,
  bool,
  int,
  Untimed,
  int,
);

final Arbitrary<Playing> anyPlaying = combine8(
  integer(min: 120, max: 1500),
  float(min: -0.5, max: 0.5),
  integer(min: 0, max: 60),
  list(
    combine2(float(min: 0, max: 1), integer(min: 500, max: 6000)),
    maxLength: 2,
  ),
  weighted<bool>([(9, constant(false)), (1, constant(true))]),
  integer(min: -150, max: 150),
  weighted<Untimed>([
    (3, constant(Untimed.none)),
    (1, choiceOf(Untimed.values)),
  ]),
  integer(min: 0, max: 1 << 20),
);

/// How the notes reached the app: a fixed latency, jitter, delivery in
/// batches, the hands of a moment arriving the other way round, and arrival
/// that keeps nothing of the playing's rhythm but its order.
typedef Arrival = (int, int, int?, bool, bool, int);

final Arbitrary<Arrival> anyArrival = combine6(
  integer(min: 0, max: 300),
  integer(min: 0, max: 40),
  optional(integer(min: 1, max: 200)),
  boolean(),
  weighted<bool>([(3, constant(false)), (1, constant(true))]),
  integer(min: 0, max: 1 << 20),
);

/// One key pressed: which, the moment it was played for, and the hand, null
/// for a note nobody asked for.
typedef Press = ({int midiNote, int moment, Hand? hand});

/// What was asked for, with [slips] applied in order, moment by moment.
List<Press> pressesOf(ExerciseRealization realization, List<Slip> slips) {
  final presses = <Press>[
    for (final moment in realization.moments)
      for (final note in moment.notes)
        (
          midiNote: note.midiNote,
          moment: moment.position,
          hand: note.hands.length == 1 ? note.hands.single : null,
        ),
  ];
  for (final (kind, at, value) in slips) {
    if (presses.isEmpty) break;
    final index = (at * presses.length).floor().clamp(0, presses.length - 1);
    final press = presses[index];
    switch (kind) {
      case 0:
        presses.removeAt(index);
      case 1:
        presses.insert(index + 1, (
          midiNote: value,
          moment: press.moment,
          hand: null,
        ));
      case 2 || 3:
        final moved = kind == 2
            ? press.midiNote + (value.isEven ? 12 : -12)
            : value;
        if (moved >= 21 && moved <= 108) {
          presses[index] = (
            midiNote: moved,
            moment: press.moment,
            hand: press.hand,
          );
        }
    }
  }
  return presses;
}

/// When each of [presses] was played, in microseconds, and what the
/// instrument reported of it, which is null where it reported nothing.
({List<int> played, List<int?> reported}) performanceTimesOf(
  List<Press> presses,
  int moments,
  Playing playing,
) {
  final (interval, drift, jitter, pauses, together, handOffset, untimed, seed) =
      playing;
  final random = math.Random(seed);
  final onsets = <int>[];
  var at = 2000000.0;
  for (var moment = 0; moment < moments; moment++) {
    onsets.add(at.round());
    if (together) continue;
    final progress = moments <= 1 ? 0.0 : moment / (moments - 1);
    at += 1000 * interval * (1 + drift * progress);
    for (final (where, extra) in pauses) {
      if ((where * moments).floor() == moment) at += 1000 * extra;
    }
  }
  final timed = [
    for (final (index, press) in presses.indexed)
      onsets[press.moment] +
          (press.hand == Hand.right ? 1000 * handOffset : 0) +
          1000 * random.nextInt(jitter + 1) +
          (press.hand == null ? 1000 * (index % 7) : 0),
  ];
  final last = presses.isEmpty ? -1 : presses.last.moment;
  return (
    played: timed,
    reported: [
      for (final (index, press) in presses.indexed)
        switch (untimed) {
          Untimed.none => timed[index],
          Untimed.all => null,
          Untimed.first when press.moment == 0 => null,
          Untimed.last when press.moment == last => null,
          Untimed.interior
              when press.moment > 0 &&
                  press.moment < last &&
                  (press.moment * 31 + seed) % 3 == 0 =>
            null,
          Untimed.oneHand when press.hand == Hand.left => null,
          _ => timed[index],
        },
    ],
  );
}

/// [presses] as they reached the app: in moment order, each moment's notes in
/// the order they arrived, with arrival times that never go backwards.
///
/// Arrival follows [playedUs], when the notes were really played, whether or
/// not the instrument reported it as [performanceUs]. Returns the transcript
/// and which press each note in it is.
(PerformanceTranscript, List<int>) arrived(
  List<Press> presses,
  List<int> playedUs,
  List<int?> performanceUs,
  Arrival arrival,
  TechnicalMaterial material,
) {
  final (latency, jitter, batch, reversed, unrelated, seed) = arrival;
  final random = math.Random(seed);
  final unrelatedStart = <int, int>{};
  var unrelatedAt = 5000;
  int arrivalOf(int index) {
    final press = presses[index];
    final played = (playedUs[index] / 1000).round();
    final base = unrelated
        ? unrelatedStart.putIfAbsent(
            press.moment,
            () => unrelatedAt += random.nextInt(3000),
          )
        : played;
    final handShift = switch ((press.hand, reversed)) {
      (Hand.left, true) => 30,
      (Hand.right, true) => -30,
      _ => 0,
    };
    final at = base + latency + handShift + random.nextInt(jitter + 1);
    return batch == null ? at : (at / batch).ceil() * batch;
  }

  final arrivals = [for (var i = 0; i < presses.length; i++) arrivalOf(i)];
  final order = List.generate(presses.length, (index) => index)
    ..sort((a, b) {
      final byMoment = presses[a].moment.compareTo(presses[b].moment);
      if (byMoment != 0) return byMoment;
      final byArrival = arrivals[a].compareTo(arrivals[b]);
      return byArrival != 0 ? byArrival : a.compareTo(b);
    });
  var transcript = PerformanceTranscript.empty;
  var latest = 0;
  for (final index in order) {
    latest = math.max(latest, arrivals[index]);
    transcript = transcript.appending(
      pitch: spellObservedPitch(presses[index].midiNote, material: material),
      timestampMs: latest,
      performanceTimeUs: performanceUs[index],
    );
  }
  return (transcript, order);
}

/// What each note edit corresponds to, naming played notes by press rather
/// than by where they fell in arrival order.
List<(int?, String, Set<Hand>, int?)> correspondenceOf(
  Alignment alignment,
  List<int> pressOfSequence,
) => [
  for (final (:realizationPosition, :edit) in alignment.noteEdits)
    (
      realizationPosition,
      edit.runtimeType.toString(),
      switch (edit) {
        Match(:final hands) ||
        Substitution(:final hands) ||
        Deletion(:final hands) => hands,
        Insertion() => const <Hand>{},
      },
      switch (edit.observedSequence) {
        final sequence? => pressOfSequence[sequence],
        null => null,
      },
    ),
]..sort((a, b) => '$a'.compareTo('$b'));

/// Everything measurement reads off the performance clock.
List<Object?> timingOf(PerformanceMeasurement measurement, Exercise exercise) =>
    [
      [for (final gap in measurement.timing.gaps) '$gap'],
      measurement.timing.paceMs,
      measurement.timing.referenceMs,
      measurement.dispersion,
      measurement.worstIntervalRatio,
      measurement.timing.longestRunWaits,
      measurement.handAsynchroniesMs,
      measurement.continuity,
      measurement.temporalStability,
      measurement.coordination,
      measurement.achievedTempoRatioFor(exercise.conditions),
    ];

void expectScore(double? value, String name) {
  if (value == null) return;
  expect(value.isFinite, isTrue, reason: '$name is $value');
  expect(value, inInclusiveRange(0, 1), reason: name);
}

/// What one measurement and its outcome promise on their own.
void checkReading(
  PerformanceMeasurement measurement,
  Outcome outcome,
  Exercise exercise,
  PerformanceTranscript transcript,
  Reached<String> reached,
) {
  for (final (name, value) in [
    ('material appeared', measurement.materialAppeared),
    ('pitch integrity', measurement.pitchIntegrity),
    ('topology accuracy', measurement.topologyAccuracy),
    ('continuity', measurement.continuity),
    ('temporal stability', measurement.temporalStability),
    ('coordination', measurement.coordination),
  ]) {
    expectScore(value, name);
  }
  for (final value in [
    measurement.timing.paceMs,
    measurement.timing.referenceMs,
    measurement.dispersion,
    measurement.worstIntervalRatio,
    measurement.medianAbsoluteHandAsynchronyMs,
    measurement.p90AbsoluteHandAsynchronyMs,
  ]) {
    if (value != null) expect(value.isFinite && value >= 0, isTrue);
  }
  final tempo = measurement.achievedTempoRatioFor(exercise.conditions);
  expect(tempo.isFinite && tempo >= 0, isTrue, reason: 'tempo ratio $tempo');
  // A pace under half a millisecond rounds to the tempo channel's sentinel
  // for no pace while the timing evidence still reports one.
  final pace = measurement.timing.paceMs;
  if (pace != null && pace < 0.5) {
    reached.add('sub-millisecond pace');
  } else {
    expect(outcome.measuredTempoRatio == null, pace == null);
  }

  // A moment is placed on the performance clock by any of its notes that
  // were, and its hands are compared only where both of theirs were.
  for (final operation in measurement.alignment.operations) {
    if (operation case MomentCorrespondence(
      :final noteEdits,
      :final performanceOnsetUs,
      :final handAsynchronyUs,
    )) {
      final byHand = <Hand, PlayedNote>{};
      final realizing = <PlayedNote>[];
      var shared = false;
      for (final edit in noteEdits) {
        if (edit
            case Match(:final hands, :final observedSequence) ||
                Substitution(:final hands, :final observedSequence)) {
          final note = transcript.notes[observedSequence];
          realizing.add(note);
          shared |= hands.length > 1;
          for (final hand in hands) {
            byHand[hand] = note;
          }
        }
      }
      if (realizing.isNotEmpty) {
        expect(
          performanceOnsetUs != null,
          realizing.any((note) => note.performanceTimeUs != null),
          reason: 'a moment is timed when any of its notes was',
        );
      }
      final left = byHand[Hand.left]?.performanceTimeUs;
      final right = byHand[Hand.right]?.performanceTimeUs;
      expect(
        handAsynchronyUs,
        shared || left == null || right == null ? isNull : right - left,
        reason: 'hands are compared where both were timed on their own keys',
      );
    }
  }

  // Waits are read only between moments the performance clock placed, and
  // never across one it did not.
  final onsets = [
    for (final operation in measurement.alignment.operations)
      if (operation case MomentCorrespondence(
        :final realizationPosition,
        :final performanceOnsetUs,
        :final noteEdits,
      ))
        if (noteEdits.any((edit) => edit is Match || edit is Substitution))
          (realizationPosition, performanceOnsetUs),
  ];
  final waits = <(int, int)>[
    for (var i = 1; i < onsets.length; i++)
      if (onsets[i - 1].$2 != null && onsets[i].$2 != null)
        (onsets[i - 1].$1, onsets[i].$1),
  ];
  expect(
    [
      for (final gap in measurement.timing.gaps)
        (gap.fromPosition, gap.toPosition),
    ],
    waits,
    reason: 'a wait joins two timed moments with nothing untimed between',
  );

  final timed = transcript.notes.any((note) => note.performanceTimeUs != null);
  if (!timed) {
    reached.add('untimed');
    expect(measurement.timing.gaps, isEmpty);
    expect(measurement.handAsynchronies, isEmpty);
    expect(outcome.continuity, isNull);
    expect(outcome.temporalStability, isNull);
    expect(outcome.coordination, isNull);
    expect(outcome.measuredTempoRatio, isNull);
  }
  if (exercise.conditions.hands != HandConfiguration.together) {
    expect(measurement.coordination, isNull, reason: 'one hand has no partner');
  }
  if (measurement.coordination != null) reached.add('coordination');
  if (measurement.continuity != null) reached.add('continuity');
  if (measurement.temporalStability != null) reached.add('stability');
}

typedef Case = (Exercise, List<Slip>, Playing, Playing, Arrival, Arrival);

void main() {
  property('timing reaches the outcome from the instrument\'s clock alone', () {
    final reached = Reached<String>({
      'untimed',
      'coordination',
      'continuity',
      'stability',
      for (final untimed in Untimed.values) 'played ${untimed.name}',
      'same correspondence under another arrival',
    });
    forAll(
      combine6(
        anyExercise,
        list(anySlip, maxLength: 3),
        anyPlaying,
        anyPlaying,
        anyArrival,
        anyArrival,
      ),
      seed: propertySeed,
      maxExamples: propertyBudget(300),
      onFalsify: reached.falsified,
      tearDownAll: reached.check,
      failingOnErrors<Case>((value) {
        final (exercise, slips, playing, replayed, arrival, rearrival) = value;
        final realization = realize(exercise);
        final presses = pressesOf(realization, slips);
        final moments = realization.moments.length;
        final times = performanceTimesOf(presses, moments, playing);
        reached.add('played ${playing.$7.name}');

        ({PerformanceMeasurement measurement, List<int> presses}) read(
          List<int?> performanceUs,
          Arrival arrival,
        ) {
          final (transcript, order) = arrived(
            presses,
            times.played,
            performanceUs,
            arrival,
            exercise.material,
          );
          final measurement = measure(
            realization: realization,
            transcript: transcript,
          );
          checkReading(
            measurement,
            outcomeFor(measurement: measurement, exercise: exercise),
            exercise,
            transcript,
            reached,
          );
          return (measurement: measurement, presses: order);
        }

        final base = read(times.reported, arrival);

        // Another arrival clock, the same playing. Arrival may regroup notes
        // into moments, and what it may not do is anything else: wherever the
        // correspondence is the same, so is every reading of time.
        final other = read(times.reported, rearrival);
        final correspondence = correspondenceOf(
          base.measurement.alignment,
          base.presses,
        );
        final regrouped = correspondenceOf(
          other.measurement.alignment,
          other.presses,
        );
        if (slips.isEmpty) {
          expect(
            '$regrouped',
            '$correspondence',
            reason:
                'the right notes in moment order align one way however '
                'they arrived',
          );
        }
        if (regrouped case final same when '$same' == '$correspondence') {
          reached.add('same correspondence under another arrival');
          expect(
            timingOf(other.measurement, exercise),
            timingOf(base.measurement, exercise),
            reason: 'arrival time is not evidence about the playing',
          );
        }

        // Another performance clock, the same arrivals. Nothing about which
        // notes were right may move.
        final retimed = read(
          performanceTimesOf(presses, moments, replayed).reported,
          arrival,
        );
        expect(
          retimed.measurement.alignment.noteEdits,
          base.measurement.alignment.noteEdits,
          reason: 'performance time does not decide correspondence',
        );
        for (final (name, count) in [
          ('produced', (PerformanceMeasurement m) => m.materialProduced),
          ('sounded', (PerformanceMeasurement m) => m.soundedCorrectly),
          ('degrees', (PerformanceMeasurement m) => m.degreesCorrect),
          ('repeats', (PerformanceMeasurement m) => m.repeats),
          ('intrusions', (PerformanceMeasurement m) => m.intrusions),
        ]) {
          expect(
            count(retimed.measurement),
            count(base.measurement),
            reason: name,
          );
        }
        expect(
          retimed.measurement.retrievedIndependently,
          base.measurement.retrievedIndependently,
        );
      }),
    );
  });
}
