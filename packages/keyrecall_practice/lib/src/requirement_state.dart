import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

/// Whether one requirement has been demonstrated to its completion target.
enum RequirementCoverage { uncovered, covered }

/// Whether one requirement warrants work at this decision instant.
enum RequirementWorkStatus { healthy, due, notYetActionable }

/// Learner-relative state for one structurally resolved requirement.
@immutable
class RequirementState {
  final ResolvedRequirement resolved;
  final RequirementCoverage coverage;
  final RequirementWorkStatus workStatus;

  const RequirementState({
    required this.resolved,
    required this.coverage,
    required this.workStatus,
  });

  bool get isCovered => coverage == RequirementCoverage.covered;
  bool get isDue => workStatus == RequirementWorkStatus.due;
}

/// Aggregate coverage, kept independent from whether anything is due.
@immutable
class ScopeCoverage {
  final int coveredTargets;
  final int targetCount;

  const ScopeCoverage({
    required this.coveredTargets,
    required this.targetCount,
  });

  bool get isComplete => coveredTargets == targetCount;
}

/// A resolved scope evaluated for one learner at one instant.
@immutable
class EvaluatedPracticeScope {
  final ResolvedPracticeScope scope;
  final List<RequirementState> requirements;
  final ScopeCoverage coverage;

  EvaluatedPracticeScope({
    required this.scope,
    required Iterable<RequirementState> requirements,
    required this.coverage,
  }) : requirements = List.unmodifiable(requirements);

  Iterable<RequirementState> get dueRequirements =>
      requirements.where((state) => state.isDue);

  bool get isCaughtUp => dueRequirements.isEmpty;
}

typedef RequirementAssessor =
    RequirementState Function({
      required ResolvedRequirement resolved,
      required LearnerState state,
      required AttemptJournal journal,
      required LearnerModel learner,
      required DateTime at,
    });

/// Applies learner-relative coverage and work policy to a structural scope.
class PracticeScopeEvaluator {
  final RequirementAssessor assess;

  const PracticeScopeEvaluator({this.assess = assessScaleRequirement});

  EvaluatedPracticeScope evaluate({
    required ResolvedPracticeScope scope,
    required LearnerState state,
    required AttemptJournal journal,
    required LearnerModel learner,
    required DateTime at,
  }) {
    final requirements = [
      for (final resolved in scope.requirements)
        assess(
          resolved: resolved,
          state: state,
          journal: journal,
          learner: learner,
          at: at,
        ),
    ];
    final targets = requirements.where(
      (state) =>
          state.resolved.requirement.role == CurriculumRequirementRole.target,
    );
    final targetList = targets.toList();
    return EvaluatedPracticeScope(
      scope: scope,
      requirements: requirements,
      coverage: ScopeCoverage(
        coveredTargets: targetList.where((state) => state.isCovered).length,
        targetCount: targetList.length,
      ),
    );
  }
}

/// The initial scale-family coverage and maintenance policy.
RequirementState assessScaleRequirement({
  required ResolvedRequirement resolved,
  required LearnerState state,
  required AttemptJournal journal,
  required LearnerModel learner,
  required DateTime at,
}) {
  final covered = journal.records.any((record) {
    if (record.exercise.material != resolved.material ||
        !resolved.requirement.constraints.matches(record.exercise)) {
      return false;
    }
    return switch (record.closure.measurement) {
      Measured(:final outcome) =>
        outcome.retrieval == FactualRetrieval.succeeded &&
            learner.executionWasManaged(outcome),
      MeasurementUnavailable() => false,
    };
  });
  if (!covered) {
    return RequirementState(
      resolved: resolved,
      coverage: RequirementCoverage.uncovered,
      workStatus: RequirementWorkStatus.due,
    );
  }

  final memory = state.materialMemory[resolved.material.materialId];
  final retrieval = memory?.retrievabilityOrPrior(at) ?? 0;
  return RequirementState(
    resolved: resolved,
    coverage: RequirementCoverage.covered,
    workStatus: retrieval < 0.75
        ? RequirementWorkStatus.due
        : RequirementWorkStatus.healthy,
  );
}
