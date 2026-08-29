import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// What a learner is actually offered, per placement tier, through the whole
/// production path.
///
/// The chain this covers is the one nothing else covers end to end: the tier
/// somebody chose at onboarding becomes the profile's immutable genesis,
/// replay propagates from it, eligibility reads the estimates it seeded, and
/// what comes out is the sequence of exercises a person sees. Every link has
/// its own tests; this asks whether they add up to a practice sequence that
/// makes sense.
void main() {
  /// The first [count] exercises presented to a learner placed at [tier].
  Future<List<Exercise>> offeredTo(PlacementTier tier, {int count = 10}) async {
    final root = Directory.systemTemp.createTempSync('keyrecall_trajectory');
    addTearDown(() => root.deleteSync(recursive: true));
    final session = await PracticeSession.open(
      store: FilePracticeStore(root),
      profile: Profile(
        id: '3f2a6c18-0000-4000-8000-00000000000a',
        displayName: 'Probe',
        createdAt: t0,
        placement: tier,
      ),
      // The production catalog, not the seven-material equivalence fixture:
      // what a learner is offered depends on how much appropriate material
      // exists, so a shorter list answers a different question.
      materials: allScales,
      learner: learner,
      sessionId: 'session-1',
    );

    final offered = <Exercise>[];
    for (var slot = 0; offered.length < count && slot < 200; slot++) {
      final at = t0.plusDays(0.5 + 0.02 * slot);
      final presented = await session.decide(at: at);
      if (presented == null) continue;
      offered.add(presented.exercise);
      // Mostly right, which is what an appropriately pitched sequence should
      // produce and what keeps this from being a study of failure.
      await session.commit(
        outcomeFor(presented.exercise, succeeded: offered.length % 3 != 0),
        observedWallTime: at,
      );
    }
    return offered;
  }

  test(
    'a beginner starts on one hand, one octave, and the first scales',
    () async {
      final offered = await offeredTo(PlacementTier.beginner);

      expect(
        offered.every((e) => e.conditions.octaves == 1),
        isTrue,
        reason:
            'the octave prerequisite reads the estimates placement seeded, so a '
            'self-reported beginner earns two octaves rather than meeting them '
            'on the way in',
      );
      expect(
        offered.every((e) => e.conditions.hands != HandConfiguration.together),
        isTrue,
        reason: 'both hands come before hands together',
      );
      expect(
        offered.every((e) => coreForms.contains(e.material.form)),
        isTrue,
        reason: 'an altered minor form is a phase away, not a key away',
      );
      expect(
        offered.every(
          (e) => admissionBandOf(
            e.material,
          ).isAtLeastAsEarlyAs(AdmissionBand.earlyTransfer),
        ),
        isTrue,
        reason:
            'the bands still hold: a beginner meeting new keys gently gets '
            'the next ones, not the black-key geographies',
      );
      expect(
        offered.map((e) => e.material).toSet(),
        hasLength(greaterThan(5)),
        reason:
            'and there is more to meet than the five foundation scales, '
            'which is what a whole band being unreachable made it',
      );
    },
  );

  test('somebody who arrived able to play is not held back', () async {
    final offered = await offeredTo(PlacementTier.advanced);

    expect(
      offered.any((e) => e.conditions.octaves == 2),
      isTrue,
      reason:
          'the floors are earned by placement as well as by practice: an '
          'artificial beginner path through material somebody already has is '
          'what the tiers exist to avoid',
    );
    expect(
      offered.any((e) => e.conditions.hands == HandConfiguration.together),
      isTrue,
    );
  });

  test('the tier a learner chose changes what they are offered', () async {
    String shapeOf(List<Exercise> offered) => [
      for (final e in offered)
        '${e.material.materialId}/${e.conditions.hands.id}/'
            '${e.conditions.octaves}',
    ].join(' ');

    final beginner = shapeOf(await offeredTo(PlacementTier.beginner));
    final advanced = shapeOf(await offeredTo(PlacementTier.advanced));

    expect(
      beginner,
      isNot(advanced),
      reason:
          'if these agreed, the question asked at onboarding would be '
          'decoration',
    );
  });
}
