import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Timing remediation: a hand whose clean attempts keep drifting is given one
/// attempt with a pulse and one without, once a session.
void main() {
  const remediation = PulseRemediationConfig();
  final remediating = SchedulerPipeline(
    learner: learner,
    config: config.withPulseRemediation(remediation),
  );
  final right = exerciseFor(materials[0]);
  final rightElsewhere = exerciseFor(materials[1]);
  final left = exerciseFor(materials[0], hands: HandConfiguration.left);
  final together = exerciseFor(materials[0], hands: HandConfiguration.together);

  Outcome played({
    double temporalStability = 0.3,
    double continuity = 0.9,
    double pitchIntegrity = 1.0,
    bool completed = true,
    FactualRetrieval retrieval = FactualRetrieval.succeeded,
    PulseMaintenance pulse = PulseMaintenance.tested,
  }) => Outcome(
    started: true,
    retrieval: retrieval,
    completed: completed,
    materialRetrieval: 1,
    pitchIntegrity: pitchIntegrity,
    continuity: continuity,
    temporalStability: temporalStability,
    achievedTempoRatio: 1,
    topologyAccuracy: 1,
    pulseMaintenance: pulse,
  );

  void record(
    PulseRemediations remediations,
    Exercise exercise,
    Outcome? outcome, {
    bool recovering = false,
  }) => remediations.record(
    exercise,
    outcome,
    recovering: recovering,
    config: remediation,
  );

  PulseRemediations qualifiedOn(Exercise exercise) {
    final remediations = PulseRemediations();
    for (var attempt = 0; attempt < remediation.observations; attempt++) {
      record(remediations, exercise, played());
    }
    return remediations;
  }

  group('qualifying', () {
    test('takes enough clean, unsteady attempts on one hand', () {
      final remediations = PulseRemediations();
      record(remediations, right, played());
      record(remediations, rightElsewhere, played());
      expect(remediations.due, isNull);

      record(remediations, right, played());

      expect(remediations.due?.stage, PulseRemediationStage.supportDue);
      expect(remediations.due?.target, right);
    });

    test('is read per hand configuration, together its own', () {
      final remediations = PulseRemediations();
      record(remediations, right, played());
      record(remediations, left, played());
      record(remediations, together, played());
      record(remediations, right, played());
      record(remediations, left, played());

      expect(remediations.due, isNull);
      expect(remediations.of(HandConfiguration.right).steadiness, hasLength(2));
      expect(
        remediations.of(HandConfiguration.together).steadiness,
        hasLength(1),
      );
    });

    test('needs every recent attempt unsteady, not most of them', () {
      final remediations = PulseRemediations();
      record(remediations, right, played());
      record(remediations, right, played(temporalStability: 0.9));
      record(remediations, right, played());

      expect(remediations.due, isNull);
    });

    test('reads no attempt whose unsteadiness could be something else', () {
      for (final (why, outcome) in [
        ('broken rather than drifting', played(continuity: 0.2)),
        ('the wrong notes', played(pitchIntegrity: 0.5)),
        ('not played through', played(completed: false)),
        ('not recalled', played(retrieval: FactualRetrieval.failed)),
        ('steadied by a pulse', played(pulse: PulseMaintenance.notTested)),
      ]) {
        final remediations = PulseRemediations();
        for (var attempt = 0; attempt < remediation.observations; attempt++) {
          record(remediations, right, outcome);
        }

        expect(remediations.due, isNull, reason: why);
      }
    });

    test('reads nothing from a recovery', () {
      final remediations = PulseRemediations();
      for (var attempt = 0; attempt < remediation.observations; attempt++) {
        record(remediations, right, played(), recovering: true);
      }

      expect(remediations.due, isNull);
    });
  });

  group('the cycle', () {
    test('is one attempt with a pulse, one without, then closed', () {
      final remediations = qualifiedOn(right);
      final cycle = remediations.due!;
      expect(cycle.bypass, ChallengeBypass.pulseSupport);

      record(remediations, right, played(pulse: PulseMaintenance.notTested));
      expect(cycle.stage, PulseRemediationStage.withdrawalDue);
      expect(cycle.bypass, ChallengeBypass.pulseWithdrawal);

      record(remediations, right, played());
      expect(cycle.stage, PulseRemediationStage.closed);
      expect(remediations.due, isNull);
    });

    test('closes whatever the withdrawal showed, and stays closed', () {
      final remediations = qualifiedOn(right);
      record(remediations, right, played());
      record(remediations, right, played(temporalStability: 0.1));
      for (var attempt = 0; attempt < 6; attempt++) {
        record(remediations, right, played(temporalStability: 0.1));
      }

      expect(remediations.due, isNull);
      expect(
        remediations.of(HandConfiguration.right).stage,
        PulseRemediationStage.closed,
      );
    });

    test('leaves the other hands to be read on their own', () {
      final remediations = qualifiedOn(right);
      record(remediations, right, played());
      record(remediations, right, played());

      for (var attempt = 0; attempt < remediation.observations; attempt++) {
        record(remediations, left, played());
      }

      expect(remediations.due?.target, left);
    });

    test('waits out a recovery', () {
      final remediations = qualifiedOn(right);
      record(remediations, left, played(), recovering: true);

      expect(remediations.due?.stage, PulseRemediationStage.supportDue);
    });

    test('lapses when a slot it could have had went elsewhere', () {
      final remediations = qualifiedOn(right);
      record(remediations, rightElsewhere, played());

      expect(remediations.due, isNull);
      expect(
        remediations.of(HandConfiguration.right).stage,
        PulseRemediationStage.closed,
      );
    });

    test('moves on from an attempt nothing measured', () {
      final remediations = qualifiedOn(right);
      record(remediations, right, null);

      expect(remediations.due?.stage, PulseRemediationStage.withdrawalDue);
    });
  });

  test('only the supported attempt is presented with a pulse', () {
    expect(
      [
        for (final bypass in ChallengeBypass.values)
          if (bypass.suppliesPulse) bypass,
      ],
      [ChallengeBypass.pulseSupport],
    );
  });

  group('the pipeline', () {
    SessionState qualifiedSession(SchedulerPipeline pipeline) {
      final session = SessionState();
      for (var attempt = 0; attempt < remediation.observations; attempt++) {
        pipeline.recordOutcome(session, right, played(), at: t0);
      }
      return session;
    }

    CandidateTrace? chosen(SessionState session) => switch (remediating.decide(
      state: stateAt(PlacementTier.advanced),
      session: session,
      candidates: allCandidates(),
      at: t0,
    )) {
      CandidateSelected(:final candidate) => candidate,
      _ => null,
    };

    test('serves the cycle ahead of ranking, then lets it go', () {
      final session = qualifiedSession(remediating);

      final supported = chosen(session)!;
      expect(supported.exercise, right);
      expect(supported.challengeBypass, ChallengeBypass.pulseSupport);
      remediating.recordOutcome(
        session,
        right,
        played(pulse: PulseMaintenance.notTested),
        at: t0,
      );

      final withdrawn = chosen(session)!;
      expect(withdrawn.exercise, right);
      expect(withdrawn.challengeBypass, ChallengeBypass.pulseWithdrawal);
      remediating.recordOutcome(session, right, played(), at: t0);

      expect(
        chosen(session)!.challengeBypass,
        isNot(
          anyOf(ChallengeBypass.pulseSupport, ChallengeBypass.pulseWithdrawal),
        ),
      );
    });

    test('gives way to recovery, and is still owed after it', () {
      final session = qualifiedSession(remediating)
        ..lastFailedExercise = exerciseFor(
          materials[1],
          guidance: GuidanceContext.notesPreviewedOnly,
        );

      final recovery = chosen(session)!;
      expect(recovery.challengeBypass, ChallengeBypass.recovery);
      remediating.recordOutcome(session, recovery.exercise, played(), at: t0);

      expect(chosen(session)!.challengeBypass, ChallengeBypass.pulseSupport);
    });

    group('a tempo probe across a cycle', () {
      final left = exerciseFor(materials[1], hands: HandConfiguration.left);
      final fast = Outcome(
        started: true,
        retrieval: FactualRetrieval.succeeded,
        completed: true,
        materialRetrieval: 1,
        pitchIntegrity: 1,
        continuity: 1,
        temporalStability: 1,
        achievedTempoRatio: 1.5,
        topologyAccuracy: 1,
      );
      final supported = played(pulse: PulseMaintenance.notTested);

      /// A right hand qualified, with or without a probe opened on the left
      /// hand just before.
      (SessionState, Exercise?) opened({required bool withProbe}) {
        final session = SessionState();
        remediating.recordOutcome(session, right, played(), at: t0);
        remediating.recordOutcome(session, right, played(), at: t0);
        if (withProbe) {
          remediating.recordOutcome(session, left, fast, at: t0);
        }
        final probe = session.tempoProbe;
        remediating.recordOutcome(session, right, played(), at: t0);
        expect(session.pulseRemediations.due, isNotNull);
        return (session, probe);
      }

      Iterable<Exercise> probesOffered(SessionState session) => [
        for (final trace in remediating.evaluate(
          state: stateAt(PlacementTier.advanced),
          session: session,
          candidates: allCandidates(),
          at: t0,
        ))
          if (trace.challengeBypass == ChallengeBypass.tempoProbe)
            trace.exercise,
      ];

      test('waiting through support and withdrawal is still waiting', () {
        final (session, probe) = opened(withProbe: true);
        expect(probe, isNotNull);

        remediating.recordOutcome(session, right, supported, at: t0);
        expect(session.tempoProbe, probe, reason: 'through the support');
        remediating.recordOutcome(session, right, played(), at: t0);
        expect(session.tempoProbe, probe, reason: 'through the withdrawal');

        expect(session.pulseRemediations.due, isNull);
        expect(probesOffered(session), [probe]);
      });

      test('waiting through a recovery that interrupts the cycle too', () {
        final (session, probe) = opened(withProbe: true);

        remediating.recordOutcome(
          session,
          right,
          played(
            pulse: PulseMaintenance.notTested,
            retrieval: FactualRetrieval.failed,
          ),
          at: t0,
        );
        final recovery = recoveryTarget(right)!;
        expect(session.lastFailedExercise, right);
        remediating.recordOutcome(session, recovery, played(), at: t0);
        expect(session.tempoProbe, probe, reason: 'through the recovery');

        remediating.recordOutcome(session, right, played(), at: t0);
        expect(session.tempoProbe, probe, reason: 'through the withdrawal');
        expect(probesOffered(session), [probe]);
      });

      test('served while a cycle is still owed, it is spent', () {
        // A scope change can leave the probe the only thing to serve while
        // the cycle's target is out of reach.
        final (session, probe) = opened(withProbe: true);

        remediating.recordOutcome(session, probe!, played(), at: t0);

        expect(session.tempoProbe, isNull);
        expect(probesOffered(session), isEmpty);
      });

      test('served and played fast, it opens the next one, not itself', () {
        final (session, probe) = opened(withProbe: true);

        remediating.recordOutcome(session, probe!, fast, at: t0);

        expect(session.tempoProbe, isNot(probe));
        expect(
          session.tempoProbe?.conditions.tempoBpm,
          greaterThan(probe.conditions.tempoBpm),
        );
      });

      test('none waiting, a fast withdrawal opens one', () {
        final (session, probe) = opened(withProbe: false);
        expect(probe, isNull);

        remediating.recordOutcome(session, right, supported, at: t0);
        expect(
          session.tempoProbe,
          isNull,
          reason: 'a supplied pulse opens none',
        );
        remediating.recordOutcome(session, right, fast, at: t0);

        expect(session.tempoProbe, right.atTempo(120));
      });
    });

    test('holds a waiting tempo probe back while it is owed', () {
      final session = qualifiedSession(remediating)
        ..tempoProbe = exerciseFor(materials[2], tempoBpm: 120);

      final traces = remediating.evaluate(
        state: stateAt(PlacementTier.advanced),
        session: session,
        candidates: allCandidates(),
        at: t0,
      );

      expect(
        traces.where(
          (trace) => trace.challengeBypass == ChallengeBypass.tempoProbe,
        ),
        isEmpty,
      );
      expect(session.tempoProbe, isNotNull);
    });

    test('never opens under a policy without remediation', () {
      final without = SchedulerPipeline(
        learner: learner,
        config: config.withPulseRemediation(null),
      );

      expect(qualifiedSession(without).pulseRemediations.due, isNull);
      expect(config.pulseRemediation, isNotNull);
    });
  });
}
