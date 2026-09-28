import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// An outcome and the presentation it closes under say the same thing about
/// the pulse, or the attempt is not written.
void main() {
  PresentationRecord presentedWith(TempoDelivery tempo) => PresentationRecord(
    policyVersion: 'v1-presentation-1',
    conditions: PresentationConditions(
      pitchCue: PitchCue.none,
      motorCue: MotorCue.none,
      performanceFeedback: PerformanceFeedback.neutralEcho,
      tempoSupport: TempoSupport.metronomeThroughout,
    ),
    delivery: PresentationDelivery(tempo: tempo),
  );

  test('a held pulse under a metronome that sounded is refused', () async {
    final session = await openSession(InMemoryPracticeStore(createdAt: t0));
    final presented =
        await session.decideOutcome(at: t0.plusDays(1)) as PresentedAttempt;
    final held = outcomeFor(presented.exercise);

    await expectLater(
      session.closeWithOutcome(
        held,
        presentation: presentedWith(
          TempoDelivery.complete(4, continuingBeats: 12),
        ),
      ),
      throwsArgumentError,
    );
    expect(session.journal.records, isEmpty);

    final record = await session.closeWithOutcome(
      held,
      presentation: presentedWith(TempoDelivery.silent(4, continuingBeats: 12)),
    );
    expect(session.journal.records, [record]);
  });
}
