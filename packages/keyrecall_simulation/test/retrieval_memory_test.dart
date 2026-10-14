import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final scale = TechnicalMaterial('C', ScaleForm.major);
  final other = TechnicalMaterial('G', ScaleForm.major);
  final start = DateTime.utc(2026);
  DateTime day(num days) =>
      start.add(Duration(minutes: (days * Duration.minutesPerDay).round()));

  SyntheticPlayer remembering({
    double spacing = 0.5,
    Map<String, double> familiarity = const {},
  }) => PlayerArchetypes.developing.copyWith(
    materialFamiliarity: familiarity,
    retrievalMemory: RetrievalMemory(
      initialHalfLifeDays: 30,
      spacingResponsiveness: spacing,
    ),
  );

  Exercise asked(GuidanceContext guidance) => Exercise.linear(
    material: scale,
    hands: HandConfiguration.right,
    guidance: guidance,
  );

  PlayerState begun(SyntheticPlayer player) => player.begin()..restUntil(start);

  test('starts each material where the player started it', () {
    final playing = begun(
      remembering(familiarity: {scale.materialId: 0.7, other.materialId: 0.3}),
    );

    expect(playing.familiarityAt(scale.materialId, start), closeTo(0.7, 1e-9));
    expect(playing.familiarityAt(other.materialId, start), closeTo(0.3, 1e-9));
  });

  test('repeated successful retrieval strengthens later recall', () {
    double recalledAfter(int successes) {
      final playing = begun(remembering());
      for (var i = 0; i < successes; i++) {
        playing.encode(scale.materialId, day(i + 1), 0.6);
      }
      return playing.familiarityAt(scale.materialId, day(60));
    }

    final recalled = [
      for (final n in [0, 1, 3, 6]) recalledAfter(n),
    ];
    for (var i = 1; i < recalled.length; i++) {
      expect(recalled[i], greaterThan(recalled[i - 1]));
    }
  });

  test('forgetting takes back what practice gave, and more', () {
    final playing = begun(remembering(familiarity: {scale.materialId: 0.5}));
    for (var i = 1; i <= 4; i++) {
      playing.encode(scale.materialId, day(i), 0.6);
    }

    expect(playing.familiarityAt(scale.materialId, day(4)), 1.0);
    expect(playing.familiarityAt(scale.materialId, day(400)), lessThan(0.5));
    expect(playing.familiarityAt(scale.materialId, day(4000)), lessThan(0.01));
  });

  test('materials left alone keep their own histories', () {
    final playing = begun(
      remembering(familiarity: {scale.materialId: 0.5, other.materialId: 0.5}),
    );
    playing.encode(scale.materialId, day(1), 0.6);

    final practised = playing.familiarityAt(scale.materialId, day(200));
    final untouched = playing.familiarityAt(other.materialId, day(200));
    expect(practised, greaterThan(untouched));
    expect(untouched, lessThan(0.5));
  });

  test('without spacing, massed and spaced encodings teach the same', () {
    double recalledLater(double spacing, Duration apart) {
      // Fully known at the start, so every gap is the schedule's own.
      final playing = begun(
        remembering(spacing: spacing, familiarity: {scale.materialId: 1}),
      );
      var at = start;
      for (var i = 0; i < 5; i++) {
        at = at.add(apart);
        playing.encode(scale.materialId, at, 0.6);
      }
      return playing.familiarityAt(
        scale.materialId,
        at.add(const Duration(days: 100)),
      );
    }

    const massed = Duration(minutes: 2);
    const spaced = Duration(days: 7);
    expect(recalledLater(0, massed), closeTo(recalledLater(0, spaced), 1e-12));
    expect(recalledLater(0, massed), inInclusiveRange(0.2, 0.95));
    expect(
      recalledLater(1, spaced),
      greaterThan(recalledLater(1, massed) + 0.1),
    );
    const daily = Duration(days: 1);
    expect(recalledLater(1, daily), closeTo(recalledLater(0, daily), 1e-12));
    expect(recalledLater(1, spaced), greaterThan(recalledLater(0, spaced)));
    expect(recalledLater(1, massed), lessThan(recalledLater(0, massed)));
  });

  test('a first encoding teaches the plain gain at any spacing', () {
    double recalledAfterFirst(double spacing) {
      final playing = begun(
        remembering(spacing: spacing, familiarity: {scale.materialId: 0.6}),
      );
      playing.encode(scale.materialId, day(1), 0.6);
      return playing.familiarityAt(scale.materialId, day(31));
    }

    // Thirty days on a half-life of 30 lengthened by the gain alone.
    final plain = math.pow(0.5, 30 / (30 * 1.6));
    for (final spacing in [0.0, 0.5, 1.0]) {
      expect(recalledAfterFirst(spacing), closeTo(plain, 1e-12));
    }
  });

  test('retrieval encodes most, previewed notes less, cued notes least', () {
    final memory = remembering().retrievalMemory!;
    double gainOf(GuidanceContext guidance, {bool retrieved = true}) =>
        memory.gainFor(guidance, started: true, retrieved: retrieved);

    expect(
      gainOf(GuidanceContext.unguided),
      greaterThan(gainOf(GuidanceContext.notesPreviewedOnly)),
    );
    expect(
      gainOf(GuidanceContext.notesPreviewedOnly),
      greaterThan(gainOf(GuidanceContext.continuouslyCued)),
    );
    expect(gainOf(GuidanceContext.continuouslyCued), greaterThan(0));
    expect(gainOf(GuidanceContext.unguided, retrieved: false), 0);
  });

  test('a failed unguided retrieval leaves the memory as it was', () {
    final playing = begun(remembering(familiarity: {scale.materialId: 0.01}));
    final before = playing.familiarityAt(scale.materialId, day(5));

    final outcome = playing.play(
      asked(GuidanceContext.unguided),
      PythonCompatibleRandom(1),
      at: day(1),
    );

    expect(outcome.retrieval, FactualRetrieval.failed);
    expect(playing.familiarityAt(scale.materialId, day(5)), before);
  });

  test('cued practice strengthens later unguided recall', () {
    final cued = begun(remembering(familiarity: {scale.materialId: 0.3}));
    for (var i = 1; i <= 10; i++) {
      cued.play(
        asked(GuidanceContext.continuouslyCued),
        PythonCompatibleRandom(i),
        at: day(i),
      );
    }
    final untouched = begun(remembering(familiarity: {scale.materialId: 0.3}));

    expect(
      cued.familiarityAt(scale.materialId, day(40)),
      greaterThan(untouched.familiarityAt(scale.materialId, day(40))),
    );
  });

  test('the practice clock only runs forward', () {
    final playing = begun(remembering());
    playing.play(
      asked(GuidanceContext.unguided),
      PythonCompatibleRandom(1),
      at: day(2),
    );

    expect(
      () => playing.play(
        asked(GuidanceContext.unguided),
        PythonCompatibleRandom(2),
        at: day(1),
      ),
      throwsStateError,
    );
    expect(
      () => playing.familiarityAt(scale.materialId, day(1)),
      throwsStateError,
    );
    expect(
      () => playing.play(
        asked(GuidanceContext.unguided),
        PythonCompatibleRandom(3),
      ),
      throwsArgumentError,
    );
  });

  test('a reading teaches nothing and moves no clock', () {
    final set = standardAssessment([scale, other]);
    List<Outcome> practised({required bool read}) {
      final playing = begun(remembering());
      final outcomes = <Outcome>[];
      for (var i = 1; i <= 6; i++) {
        if (read) assess(set, playing, at: day(i + 30));
        outcomes.add(
          playing.play(
            asked(GuidanceContext.unguided),
            PythonCompatibleRandom(i),
            at: day(i),
          ),
        );
      }
      return outcomes;
    }

    final plain = practised(read: false);
    final read = practised(read: true);
    for (final (i, outcome) in plain.indexed) {
      expect(read[i].retrieval, outcome.retrieval, reason: 'attempt $i');
      expect(read[i].materialRetrieval, outcome.materialRetrieval);
      expect(read[i].pitchIntegrity, outcome.pitchIntegrity);
    }
  });

  test('acquisition work encodes the material it rehearses', () {
    final task = AcquisitionTask(
      parent: asked(GuidanceContext.continuouslyCued),
      timing: TimingDemand.unmetered,
      advancement: TaskAdvancement.learnerDriven,
    );
    final playing = begun(remembering(familiarity: {scale.materialId: 0.3}));
    final before = playing.familiarityAt(scale.materialId, day(30));

    performAcquisition(
      state: playing,
      task: task,
      rng: PythonCompatibleRandom(1),
      at: day(1),
    );

    expect(
      playing.familiarityAt(scale.materialId, day(30)),
      greaterThan(before),
    );
  });

  test('a player without retrieval memory ignores the instant', () {
    final player = PlayerArchetypes.developing;
    final exercise = asked(GuidanceContext.notesPreviewedOnly);
    final timed = player.begin()..restUntil(start);
    final untimed = player.begin()..restUntil(start);
    for (var i = 1; i <= 20; i++) {
      final a = timed.play(exercise, PythonCompatibleRandom(i), at: day(i));
      final b = untimed.play(exercise, PythonCompatibleRandom(i));
      expect(a.retrieval, b.retrieval);
      expect(a.materialRetrieval, b.materialRetrieval);
    }
    expect(
      timed.familiarityOf(scale.materialId),
      untimed.familiarityOf(scale.materialId),
    );
    expect(
      () => timed.familiarityAt(scale.materialId, day(1)),
      throwsStateError,
    );
  });
}
