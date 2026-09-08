import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'candidate_trace.dart';
import 'novelty_load.dart';

/// A decision-time census and the strongest contenders in each family and hand.
String selectionDiagnostics({
  required List<CandidateTrace> traces,
  required Map<String, List<CandidateTrace>> stages,
  required CandidateTrace? winner,
  required LearnerState state,
  required String pacing,
  required String introductions,
  required bool freshProbe,
  required Exercise? tempoProbe,
  required bool guidanceService,
  bool acquisitionFallback = false,
}) {
  final admitted = traces.where((trace) => trace.isRanked).toList();
  final available = stages.values.last;
  final availableSet = available.toSet();
  final positions = {for (final (i, trace) in traces.indexed) trace: i};
  final membership = {
    for (final entry in stages.entries) entry.key: entry.value.toSet(),
  };
  List<CandidateTrace> ranked(Iterable<CandidateTrace> candidates) =>
      candidates.toList()..sort((a, b) {
        final order = b.rankKey!.compareTo(a.rankKey!);
        return order == 0 ? positions[a]!.compareTo(positions[b]!) : order;
      });
  String status(CandidateTrace trace) {
    for (final entry in membership.entries) {
      if (!entry.value.contains(trace)) return 'removed:${entry.key}';
    }
    return 'selectable';
  }

  final groups = <String, List<CandidateTrace>>{};
  for (final trace in traces) {
    final exercise = trace.exercise;
    groups
        .putIfAbsent(
          '${exercise.material.familyId}/${exercise.conditions.hands.id}',
          () => [],
        )
        .add(trace);
  }
  final top = <CandidateTrace>{
    ?winner,
    ...ranked(admitted).take(5),
    ...ranked(available).take(5),
    for (final group in groups.values)
      ...ranked(group.where((trace) => trace.isRanked)).take(1),
    for (final group in groups.values)
      ...ranked(group.where(availableSet.contains)).take(1),
    for (final trace in admitted)
      if (trace.exercise == tempoProbe) trace,
  };
  final scales = ranked(
    available.where((trace) => trace.exercise.material is ScaleMaterial),
  );
  final bestScale = scales.firstOrNull;
  final probe = admitted.where((trace) => trace.exercise == tempoProbe);
  return [
    'selection diagnostics v1; captured at decision time; not learner evidence',
    'generated=${traces.length} admitted=${admitted.length} '
        '${stages.entries.map((e) => '${e.key}=${e.value.length}').join(' ')}',
    'pacing=$pacing introductions=$introductions '
        'fresh_probe=$freshProbe probe=${probe.isEmpty ? 'not_admitted' : status(probe.first)} '
        'guidance_service=$guidanceService',
    if (acquisitionFallback) 'acquisition_fallback=true',
    'rank order: tier, coordination_transition, contrary_coordination, '
        'retention, information, diversity, focus, realization, realization_fit; '
        'higher wins; exact ties use candidate order',
    'pacing, introductions, echo and novelty are filters, not score adjustments',
    for (final entry in groups.entries)
      'family_hand=${entry.key} generated=${entry.value.length} '
          'admitted=${entry.value.where((t) => t.isRanked).length} '
          'selectable=${entry.value.where(availableSet.contains).length} '
          'eligibility=${_counts(entry.value.map((t) => t.eligibility.code.id))} '
          'admission=${_counts(entry.value.map((t) => !t.challengeStatus.isReached
              ? 'not_reached'
              : t.challengeSurvived
              ? 'survived'
              : 'refused:${t.admissionRefusal?.name ?? 'unspecified'}'))}',
    'winner_vs_best_selectable_scale=${bestScale == null
            ? 'no_selectable_scale'
            : winner == bestScale
            ? 'winner_is_scale'
            : guidanceService
            ? 'overdue_guidance_probe_service'
            : rankDifference(winner!.rankKey!, bestScale.rankKey!)} '
        'scale_candidate=${bestScale == null ? '-' : positions[bestScale]}',
    'contenders: winner, top 5 admitted, top 5 selectable, '
        'best admitted/selectable per family/hand, pending tempo probe',
    for (final trace in ranked(top))
      'candidate=${positions[trace]} winner=${trace == winner} '
          '${trace.exercise.material.materialId} '
          'family=${trace.exercise.material.familyId} '
          '${trace.exercise.conditions.hands.id} '
          '${trace.exercise.conditions.handMotion.id} '
          '${trace.exercise.conditions.octaves}oct '
          '${trace.exercise.conditions.direction.id} '
          '${trace.exercise.conditions.tempoBpm}bpm '
          'g=${trace.exercise.guidance.independence} '
          'admitted_by=${trace.challengeBypass?.id ?? 'in-band'} '
          'p=${trace.prediction.overallP} in_band=${trace.isWithinChallengeBand} '
          'novelty_load=${noveltyLoadOf(state, trace.exercise)} '
          '${status(trace)} rank=${_rankValues(trace.rankKey!)}',
  ].join('\n');
}

Map<String, int> _counts(Iterable<String> values) {
  final counts = <String, int>{};
  for (final value in values) {
    counts.update(value, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

Map<String, num> _rankValues(RankKey key) => {
  'tier': key.tier.index,
  'coordination_transition': key.coordinationTransition ? 1 : 0,
  'contrary_coordination': key.contraryCoordination ? 1 : 0,
  'retention': key.retention,
  'information': key.information,
  'diversity': key.diversity,
  'focus': key.goals,
  'realization': key.realization.index,
  'realization_fit': key.realizationFit,
};

/// The first unequal field in the scheduler's lexicographic comparison.
String rankDifference(RankKey winner, RankKey alternative) {
  final other = _rankValues(alternative);
  for (final entry in _rankValues(winner).entries) {
    if (entry.value != other[entry.key]) {
      return '${entry.key}:${entry.value}>${other[entry.key]}';
    }
  }
  return 'exact_rank_tie_candidate_order';
}
