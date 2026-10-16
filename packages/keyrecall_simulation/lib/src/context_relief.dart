import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

/// What one allocation-served attempt showed about its execution context.
enum ServiceEvidence {
  notStarted,
  incomplete,

  /// Completed without a motor score, so execution is unresolved.
  untimed,

  /// Timed and not managed: the only evidence that counts toward relief.
  unmanaged,
  managed;

  static ServiceEvidence of(
    Outcome outcome, {
    LearnerModel learner = const LearnerModel(),
  }) {
    if (!outcome.started) return notStarted;
    if (learner.executionWasManaged(outcome)) return managed;
    if (outcome.motorScore != null) return unmanaged;
    if (!outcome.completed) return incomplete;
    return untimed;
  }
}

/// A shared bound on how much of allocation's service one execution group
/// can take after repeated unsuccessful service.
///
/// A group is a family and a hand configuration, so hands-together
/// arpeggios share one budget whatever the material. Allocation-served
/// attempts that were timed and not managed count against the strand they
/// played until that strand is managed by any route; once a group's strands
/// hold [trigger] of them between them, the group is relieved. While relieved,
/// it may be served at no more than [budget] of its last [window]
/// opportunities, an opportunity being an allocatable decision at which
/// allocation would otherwise have served it.
///
/// Relief changes only allocation's priority. Coverage, eligibility, waiting,
/// ranking, recovery, and the learner's estimates are untouched, and the
/// window advances only with opportunities, never with time or outcomes.
class ContextRelief {
  final int trigger;
  final int budget;
  final int window;

  final Map<ExecutionContext, int> _unsuccessful = {};
  final Map<ExecutionContext, String> _groups = {};
  final Map<String, List<bool>> _opportunities = {};
  final Set<int> _allocated = {};
  final Map<ServiceEvidence, int> _evidence = {};
  int _settled = 0;
  int _served = 0;
  int _withheld = 0;
  int _alternatives = 0;

  ContextRelief({
    required this.trigger,
    required this.budget,
    required this.window,
  });

  static String groupOf(Exercise exercise) =>
      '${exercise.material.familyId} ${exercise.conditions.hands.id}';

  /// Whether [group] has accumulated enough unsuccessful service to be
  /// bounded.
  bool isRelieved(String group) =>
      _unsuccessful.entries
          .where((e) => _groups[e.key] == group)
          .fold(0, (sum, e) => sum + e.value) >=
      trigger;

  /// Whether allocation may serve [group] at this opportunity, recording the
  /// opportunity when the group is relieved.
  bool admit(String group) {
    if (!isRelieved(group)) return true;
    final earlier = _opportunities.putIfAbsent(group, () => []);
    final admitted = earlier.where((served) => served).length < budget;
    earlier.add(admitted);
    if (earlier.length >= window) earlier.removeAt(0);
    admitted ? _served++ : _withheld++;
    return admitted;
  }

  /// Notes that a withheld requirement was served by a realization outside
  /// the withheld group instead.
  void usedAlternative() => _alternatives++;

  /// Notes that allocation served the attempt at [journalIndex].
  void serve(int journalIndex) => _allocated.add(journalIndex);

  /// Reads every attempt written since the last settle.
  void settle(AttemptJournal journal, LearnerModel learner) {
    final records = journal.records;
    for (; _settled < records.length; _settled++) {
      final record = records[_settled];
      final allocated = _allocated.remove(_settled);
      if (record.closure.measurement case Measured(:final outcome)) {
        observe(
          record.exercise,
          ServiceEvidence.of(outcome, learner: learner),
          allocated: allocated,
        );
      }
    }
  }

  /// What one attempt at [exercise] showed, whether or not allocation chose
  /// it.
  void observe(
    Exercise exercise,
    ServiceEvidence evidence, {
    required bool allocated,
  }) {
    final strand = executionContextOf(exercise);
    _groups[strand] = groupOf(exercise);
    if (evidence == ServiceEvidence.managed) _unsuccessful.remove(strand);
    if (!allocated) return;
    _evidence[evidence] = (_evidence[evidence] ?? 0) + 1;
    if (evidence == ServiceEvidence.unmanaged) {
      _unsuccessful[strand] = (_unsuccessful[strand] ?? 0) + 1;
    }
  }

  Map<String, num> get diagnostics => {
    for (final evidence in ServiceEvidence.values)
      'relief evidence ${evidence.name}': _evidence[evidence] ?? 0,
    'relief served while relieved': _served,
    'relief withheld': _withheld,
    'relief alternative realizations': _alternatives,
  };
}
