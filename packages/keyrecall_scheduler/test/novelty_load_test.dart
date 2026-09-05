import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// How many ways of playing arrive at once, and what that asks of guidance.
void main() {
  final material = materials.first;
  const novelty = NoveltyConfig();

  /// A learner who has played [material] with each hand separately, one
  /// octave, in the only motion a single hand has, and is ready to put them
  /// together.
  LearnerState separateHands({PlacementTier tier = PlacementTier.advanced}) {
    final state = learner.placementState(tier, at: t0);
    for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
      state.materialExecutionFor(
          (material.materialId, hands, HandMotion.parallel),
          t0,
          learnerParams,
        )
        ..demonstrate(octaves: 1, tempoBpm: 80)
        ..readyForHandsTogether(octaves: 1, tempoBpm: 80)
        ..lastEvidenceAt = t0;
    }
    state.materialMemoryFor(material.materialId, learnerParams)
      ..memoryAnchorAt = t0
      ..factualLastRetrievalAt = t0
      ..lastRetrievalAttemptAt = t0
      ..establishedIndependence = GuidanceContext.unguided.independence
      ..establishedIndependenceAt = t0;
    return state;
  }

  Exercise exercise({
    HandConfiguration hands = HandConfiguration.together,
    HandMotion motion = HandMotion.parallel,
    int octaves = 1,
    GuidanceContext guidance = GuidanceContext.unguided,
  }) => exerciseFor(
    material,
    hands: hands,
    handMotion: motion,
    octaves: octaves,
    guidance: guidance,
  );

  group('what counts as novel', () {
    test('a familiar hand at a familiar span is nothing new', () {
      expect(
        noveltyLoadOf(
          separateHands(),
          exercise(hands: HandConfiguration.right),
        ),
        0,
      );
    });

    test('a first hands-together attempt is one new way of playing', () {
      expect(noveltyLoadOf(separateHands(), exercise()), 1);
    });

    test('a first contrary motion beside it is a second', () {
      expect(
        noveltyLoadOf(separateHands(), exercise(motion: HandMotion.contrary)),
        2,
      );
    });

    test('a span is new only where the hands are already familiar', () {
      expect(
        noveltyLoadOf(
          separateHands(),
          exercise(hands: HandConfiguration.right, octaves: 2),
        ),
        1,
      );
      expect(
        noveltyLoadOf(separateHands(), exercise(octaves: 2)),
        1,
        reason: 'a configuration nobody has used has no span to have covered',
      );
    });
  });

  group('what novelty asks of guidance', () {
    test('one new way of playing may still be asked for from memory', () {
      expect(
        allowedIndependence(1, novelty),
        GuidanceContext.unguided.independence,
      );
    });

    test('two keep the notes on screen at least once', () {
      expect(
        allowedIndependence(2, novelty),
        GuidanceContext.notesPreviewedOnly.independence,
      );
    });

    test('three are met with the material in view', () {
      expect(
        allowedIndependence(3, novelty),
        GuidanceContext.continuouslyCued.independence,
      );
    });
  });

  group('what the slot does with it', () {
    /// Everything the slot would rank, for a learner ready to put the hands
    /// together on material they can already retrieve unaided.
    List<CandidateTrace> ranked(LearnerState state) => pipeline
        .evaluate(
          state: state,
          session: SessionState(),
          candidates: [
            exercise(motion: HandMotion.contrary),
            exercise(
              motion: HandMotion.contrary,
              guidance: GuidanceContext.notesPreviewedOnly,
            ),
          ],
          at: t0,
        )
        .where((trace) => trace.isRanked)
        .toList();

    test('the stack the device produced is set aside for a supported one', () {
      final state = separateHands();
      final available = ranked(state);

      expect(
        available.where((trace) => trace.exercise.guidance.independence == 2),
        isNotEmpty,
        reason:
            'the unsupported stack is admissible; the rule is what stops it',
      );

      final kept = withNoveltySupported(available, state, novelty);

      expect(
        kept.where((trace) => trace.exercise.guidance.independence == 2),
        isEmpty,
        reason: 'first hands together and first contrary, from memory',
      );
      expect(kept, isNotEmpty);
    });

    test('nothing is set aside when nothing else is on offer', () {
      final state = separateHands();
      final onlyStacked = [
        for (final trace in ranked(state))
          if (trace.exercise.guidance.independence == 2) trace,
      ];

      expect(
        withNoveltySupported(onlyStacked, state, novelty),
        onlyStacked,
        reason: 'the alternative to a demanding candidate is nothing at all',
      );
    });
  });
}
