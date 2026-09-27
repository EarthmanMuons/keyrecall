import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// Coverage read from targets and history alone agrees with what the full
/// evaluator reports, without generating anything to get there.
void main() {
  final catalog = <TechnicalMaterial>[
    ...allScales,
    ...allRootPositionArpeggios,
  ];

  for (final (goalId, focus) in [
    ('FOUNDATIONS', PracticeFocus.unrestricted),
    ('KEY_FLUENCY_24', PracticeFocus.unrestricted),
    (
      PracticeGoal.generalFluency.id,
      PracticeFocus(
        exclusiveRequirementIds: {
          catalogRequirementId(
            PracticeGoal.generalFluency.id,
            ScaleMaterial('C', ScaleForm.major).materialId,
          ),
        },
      ),
    ),
  ]) {
    final goal = goalId == PracticeGoal.generalFluency.id
        ? PracticeGoal.generalFluency
        : supportedGoals[goalId]!;

    test('$goalId targets are the resolver\'s', () {
      final resolved =
          (PracticeScopeResolver().resolve(
                    goal: goal,
                    focus: focus,
                    catalog: catalog,
                    instrument: InstrumentProfile(),
                  )
                  as ValidPracticeScope)
              .scope;

      expect(
        {
          for (final target in PracticeScopeResolver().targetsOf(
            goal: goal,
            focus: focus,
            catalog: catalog,
          ))
            target.requirement.id,
        },
        {
          for (final requirement in resolved.requirements)
            if (requirement.isTarget) requirement.requirement.id,
        },
      );
    });

    test('$goalId coverage agrees with the evaluator', () async {
      final store = InMemoryPracticeStore(createdAt: t0);
      final session = await openSession(store, materials: catalog);
      session.updateScope(goal: goal, focus: focus);
      await practise(session, attempts: 12);
      final evaluated = const PracticeScopeEvaluator().evaluate(
        scope:
            (PracticeScopeResolver().resolve(
                      goal: goal,
                      focus: focus,
                      catalog: catalog,
                      instrument: InstrumentProfile(),
                    )
                    as ValidPracticeScope)
                .scope,
        state: session.state,
        journal: session.journal,
        learner: session.learner,
        at: t0.plusDays(1000),
      );

      final read = coverageOf(
        PracticeScopeResolver().targetsOf(
          goal: goal,
          focus: focus,
          catalog: catalog,
        ),
        session.journal.records,
      );

      if (goalId != 'KEY_FLUENCY_24') {
        expect(
          read.coveredTargets,
          greaterThan(0),
          reason: 'so the agreement below is about something',
        );
      }
      expect(read.coveredTargetIds, evaluated.coverage.coveredTargetIds);
      expect(read.targetCount, evaluated.coverage.targetCount);
    });
  }
}
