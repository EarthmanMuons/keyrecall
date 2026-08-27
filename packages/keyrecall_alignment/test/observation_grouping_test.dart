import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_alignment/keyrecall_alignment.dart';

import 'support/recorded_takes.dart';

void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);

  PerformanceTranscript transcriptFrom(List<(int, int)> notes) {
    var transcript = PerformanceTranscript.empty;
    for (final (midiNote, timestampMs) in notes) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: material),
        timestampMs: timestampMs,
      );
    }
    return transcript;
  }

  /// Steady playing at [gapMs], for cases the corpus does not contain.
  PerformanceTranscript steady(int gapMs, {int count = 4}) =>
      transcriptFrom([for (var i = 0; i < count; i++) (60 + i, i * gapMs)]);

  group('what a boundary is', () {
    test('one per adjacent pair, in arrival order', () {
      for (final name in recordedTakes.keys) {
        final transcript = transcriptOf(name);
        final grouping = groupObservations(transcript: transcript);

        expect(grouping.boundaries.length, transcript.length - 1, reason: name);
        expect(
          grouping.boundaries.map((b) => (b.beforeSequence, b.afterSequence)),
          [for (var i = 1; i < transcript.length; i++) (i - 1, i)],
          reason: name,
        );
      }
    });

    test('a transcript too short to have a gap has no boundaries', () {
      expect(
        groupObservations(transcript: PerformanceTranscript.empty).boundaries,
        isEmpty,
      );
      expect(
        groupObservations(transcript: steady(500, count: 1)).boundaries,
        isEmpty,
      );
    });
  });

  group('what timing may contribute', () {
    test('both readings stay affordable at every gap', () {
      const policy = AlignmentPolicy.standard;

      for (final name in recordedTakes.keys) {
        for (final boundary in groupObservations(
          transcript: transcriptOf(name),
        ).boundaries) {
          expect(boundary.sameMomentCost, inInclusiveRange(0, 2), reason: name);
          expect(
            boundary.splitMomentCost,
            inInclusiveRange(0, 2),
            reason: name,
          );
          expect(
            (boundary.sameMomentCost - boundary.splitMomentCost).abs(),
            lessThanOrEqualTo(policy.maxGroupingPreference),
            reason: name,
          );
        }
      }
    });

    test('the preference is bounded by the policy that owns the costs', () {
      const indifferent = AlignmentPolicy(maxGroupingPreference: 0);

      for (final boundary in groupObservations(
        transcript: transcriptOf('comfortable-c-major'),
        alignmentPolicy: indifferent,
      ).boundaries) {
        expect(boundary.sameMomentCost, 0);
        expect(boundary.splitMomentCost, 0);
        expect(boundary.lean, BoundaryLean.ambiguous);
      }
    });

    test('no gap ever costs a substitution more than its alternative', () {
      const policy = AlignmentPolicy.standard;
      final wide = groupObservations(transcript: steady(10000)).boundaries;
      final tight = groupObservations(transcript: steady(0)).boundaries;

      for (final boundary in [...wide, ...tight]) {
        expect(
          (boundary.sameMomentCost - boundary.splitMomentCost).abs(),
          policy.maxGroupingPreference,
        );
        expect(
          [
            boundary.sameMomentCost,
            boundary.splitMomentCost,
          ].reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(policy.substitutionCost),
        );
      }
    });
  });

  group('what timing may not see', () {
    test('the same arrivals price the same however they are spelled', () {
      const timings = [0, 20, 500, 620, 1000];
      final scale = transcriptFrom([
        for (final (index, at) in timings.indexed) (60 + index, at),
      ]);
      final noise = transcriptFrom([
        for (final (index, at) in timings.indexed) (61 + index * 5, at),
      ]);

      expect(
        groupObservations(transcript: scale),
        groupObservations(transcript: noise),
      );
    });

    test('one transcript always groups the same way', () {
      for (final name in recordedTakes.keys) {
        expect(
          groupObservations(transcript: transcriptOf(name)),
          groupObservations(transcript: transcriptOf(name)),
          reason: name,
        );
      }
    });
  });

  group('what the recorded playing produces', () {
    test('all three leans appear across the corpus', () {
      final leans = {
        for (final name in recordedTakes.keys)
          for (final boundary in groupObservations(
            transcript: transcriptOf(name),
          ).boundaries)
            boundary.lean,
      };

      expect(leans, BoundaryLean.values.toSet());
    });

    test('comfortable playing lands outside the ambiguous region', () {
      final leans = {
        for (final boundary in groupObservations(
          transcript: transcriptOf('comfortable-c-major'),
        ).boundaries)
          boundary.lean,
      };

      expect(leans, {BoundaryLean.sameMoment, BoundaryLean.separateMoments});
    });

    test('where confidence ends is the grouping policy to say', () {
      final transcript = steady(100, count: 2);

      expect(
        groupObservations(transcript: transcript).boundaries.single.lean,
        BoundaryLean.ambiguous,
      );
      expect(
        groupObservations(
          transcript: transcript,
          policy: const ObservationGroupingPolicy(
            confidentlySameMs: 120,
            confidentlySeparateMs: 400,
          ),
        ).boundaries.single.lean,
        BoundaryLean.sameMoment,
      );
    });

    test('a gap of 23 ms leans together and stays splittable', () {
      final grouping = groupObservations(
        transcript: transcriptOf('hands-out-of-phase-c-major'),
      );
      final closest = grouping.boundaries.reduce(
        (a, b) => a.gapMs <= b.gapMs ? a : b,
      );

      expect(closest.gapMs, lessThan(50));
      expect(closest.lean, BoundaryLean.sameMoment);
      expect(
        closest.splitMomentCost,
        lessThanOrEqualTo(AlignmentPolicy.standard.substitutionCost),
        reason:
            'notes this close belonged to different moments in this take, '
            'so splitting here has to remain purchasable',
      );
    });

    test('arrivals sharing a millisecond are boundaries like any other', () {
      final simultaneous = [
        for (final boundary in groupObservations(
          transcript: transcriptOf('comfortable-c-major'),
        ).boundaries)
          if (boundary.gapMs == 0) boundary,
      ];

      expect(simultaneous, isNotEmpty);
      expect(
        simultaneous.every(
          (boundary) => boundary.lean == BoundaryLean.sameMoment,
        ),
        isTrue,
      );
    });
  });
}
