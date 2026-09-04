import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

import 'candidate_trace.dart';
import 'config/scheduler_config.dart';

/// What an introduction cap counts unresolved introductions over.
enum IntroductionScope {
  /// One budget per declared material family.
  family,

  /// One budget for everything in scope.
  catalog,
}

/// What the introduction cap did to one slot's available set.
enum IntroductionDisposition {
  /// No policy is configured, or no scope reached its cap.
  inactive,

  /// The cap held because every available candidate would widen the catalog.
  unrelieved,

  /// Breadth-adding candidates were withheld in favor of established work.
  withheld,
}

/// The available set after the introduction cap, and what it did to reach it.
@immutable
class IntroductionDecision {
  final List<CandidateTrace> selectable;
  final IntroductionDisposition disposition;

  /// Unresolved introductions per scope key at the moment of the decision.
  final Map<String, int> unresolved;

  /// Candidates the cap removed.
  final int withheld;

  IntroductionDecision.inactive(this.selectable, {this.unresolved = const {}})
    : disposition = IntroductionDisposition.inactive,
      withheld = 0;

  IntroductionDecision.unrelieved(this.selectable, {required this.unresolved})
    : disposition = IntroductionDisposition.unrelieved,
      withheld = 0;

  IntroductionDecision.withheld(
    this.selectable, {
    required this.unresolved,
    required this.withheld,
  }) : disposition = IntroductionDisposition.withheld;
}

/// Materials met but not yet retrieved, counted per scope key.
///
/// Unresolved is factual rather than predicted, the same question consolidation
/// asks: the learner has been shown this material and has never produced it
/// from memory. A material whose family no candidate names is not counted,
/// because work outside the current scope cannot be what the slot chooses
/// between.
Map<String, int> unresolvedIntroductions({
  required LearnerState state,
  required Map<String, String> materialFamilies,
  required IntroductionConfig config,
}) {
  final unresolved = <String, int>{};
  for (final entry in state.materialMemory.entries) {
    if (entry.value.hasFactualRetrieval) continue;
    final family = materialFamilies[entry.key];
    if (family == null) continue;
    final key = config.scopeKeyFor(family);
    unresolved[key] = (unresolved[key] ?? 0) + 1;
  }
  return unresolved;
}

/// Whether admitting [trace] would widen the catalog rather than deepen it.
///
/// The other hand of a material already met is not breadth: it deepens work
/// the learner has started, and withholding it would make the cap an argument
/// about hands rather than about how many new things are open at once.
bool widensCatalog(CandidateTrace trace, LearnerState state) =>
    trace.challengeBypass == ChallengeBypass.newMaterial &&
    !state.materialMemory.containsKey(trace.exercise.material.materialId);
