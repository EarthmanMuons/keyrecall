import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'package:keyrecall/features/practice/attempt_review.dart';

/// What the screen between attempts is allowed to say.
void main() {
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
  );

  Outcome outcomeOf({
    bool started = true,
    bool completed = true,
    FactualRetrieval retrieval = FactualRetrieval.succeeded,
    double pitchIntegrity = 1.0,
    double continuity = 1.0,
    double temporalStability = 1.0,
  }) => Outcome(
    started: started,
    retrieval: retrieval,
    completed: completed,
    materialRetrieval: pitchIntegrity,
    pitchIntegrity: pitchIntegrity,
    continuity: continuity,
    temporalStability: temporalStability,
    achievedTempoRatio: 1.0,
    topologyAccuracy: pitchIntegrity,
  );

  group('praise', () {
    test('says the strongest true thing', () {
      expect(praiseFor(exercise, outcomeOf()), 'Every note, from memory.');
      expect(
        praiseFor(exercise, outcomeOf(retrieval: FactualRetrieval.notTested)),
        'Every note right.',
      );
    });

    test('falls back through what actually held up', () {
      // Wrong notes, but the pulse never wavered.
      expect(
        praiseFor(exercise, outcomeOf(pitchIntegrity: 0.5)),
        'Nice and steady the whole way.',
      );
      // Wrong notes and uneven, but unbroken.
      expect(
        praiseFor(
          exercise,
          outcomeOf(pitchIntegrity: 0.5, temporalStability: 0.2),
        ),
        'Straight through, no stopping.',
      );
    });

    test('invents nothing for an attempt that never started', () {
      expect(
        praiseFor(
          exercise,
          outcomeOf(
            started: false,
            completed: false,
            retrieval: FactualRetrieval.failed,
            pitchIntegrity: 0.0,
            continuity: 0.0,
            temporalStability: 0.0,
          ),
        ),
        isNull,
        reason: 'declining is not an achievement, and saying so would be a lie',
      );
    });

    test('invents nothing for an attempt that fell apart', () {
      expect(
        praiseFor(
          exercise,
          outcomeOf(
            completed: false,
            retrieval: FactualRetrieval.failed,
            pitchIntegrity: 0.1,
            continuity: 0.1,
            temporalStability: 0.1,
          ),
        ),
        isNull,
      );
    });
  });
}
