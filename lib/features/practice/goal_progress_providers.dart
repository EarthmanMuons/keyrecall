import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'goal_progress.dart';
import 'practice_providers.dart';

/// Progress toward the goal in force, or null where there is no finish line
/// or no session is open.
///
/// Read from the goal's targets and the history alone. It does not wait on a
/// scheduling decision, so it is there while an attempt is pending or under
/// review, and it never generates the candidates a decision would.
///
/// General technique has no finish line, so it has no progress here; the
/// fluency report is what describes open-ended practice.
final goalProgressProvider = Provider<GoalProgress?>((ref) {
  final targets = ref.watch(goalTargetsProvider);
  final loop = ref.watch(practiceLoopProvider).value;
  if (targets == null || loop == null) return null;
  return goalProgressOf(
    targets,
    coverageOf(targets, loop.session.journal.records),
  );
});

/// What the active scope counts toward, or null where it has no finish line.
final goalTargetsProvider = Provider<List<GoalTarget>?>((ref) {
  final plan = ref.watch(
    practiceLoopProvider.select((loop) => loop.value?.plan),
  );
  if (plan == null || !hasFinishLine(plan)) return null;
  final catalog = ref.watch(practiceCatalogProvider);
  if (plan.resolve(catalog) case ResolvedPlan(:final goal, :final focus)) {
    return PracticeScopeResolver().targetsOf(
      goal: goal,
      focus: focus,
      catalog: catalog,
    );
  }
  return null;
});
