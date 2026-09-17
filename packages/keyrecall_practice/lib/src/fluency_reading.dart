import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'fluency_history.dart';

/// The fluency report's own rule for when a tempo observation demonstrates a
/// pace.
///
/// Report policy, deliberately separate from `LearnerModel`'s managed-execution
/// threshold even where the values agree: calibrating the learner model must
/// not rewrite what a learner's history says they demonstrated. Changing it is
/// a change to [id].
@immutable
class TempoQualification {
  final String id;
  final double minimumMotorScore;

  const TempoQualification({required this.id, required this.minimumMotorScore});

  static const TempoQualification v1 = TempoQualification(
    id: 'FLUENCY_TEMPO_1',
    minimumMotorScore: 0.5,
  );

  bool qualifies(TempoObservation observation) =>
      observation.motorScore >= minimumMotorScore;

  /// The pace [observation] demonstrates: what was played, capped at what was
  /// asked for.
  double tempoOf(TempoObservation observation) => math.min(
    observation.requestedTempoBpm,
    observation.requestedTempoBpm * observation.tempoRatio,
  );
}

/// The strongest level each material has ever been demonstrated at, with when
/// it was last reached.
///
/// Monotonic over prefixes of [days]: a later day can raise a level or move its
/// date forward, never lower it.
Map<String, Demonstration> bestDemonstrations(Iterable<FluencyDay> days) {
  final best = <String, Demonstration>{};
  for (final day in days) {
    for (final demonstration in day.demonstrations.values) {
      best.update(
        demonstration.materialId,
        (held) => held.mergedWith(demonstration),
        ifAbsent: () => demonstration,
      );
    }
  }
  return best;
}

/// Where a demonstrated tempo applies.
typedef TempoContext = ({
  String materialId,
  HandConfiguration hands,
  HandMotion handMotion,
  int octaves,
  int guidanceIndependence,
});

/// The fastest qualifying pace in each context, with guidance kept apart.
Map<TempoContext, double> demonstratedTempos(
  Iterable<FluencyDay> days, {
  TempoQualification qualification = TempoQualification.v1,
}) {
  final fastest = <TempoContext, double>{};
  for (final observation in days.expand((day) => day.tempos)) {
    if (!qualification.qualifies(observation)) continue;
    final context = (
      materialId: observation.materialId,
      hands: observation.hands,
      handMotion: observation.handMotion,
      octaves: observation.octaves,
      guidanceIndependence: observation.guidanceIndependence,
    );
    final tempo = qualification.tempoOf(observation);
    fastest.update(
      context,
      (held) => math.max(held, tempo),
      ifAbsent: () => tempo,
    );
  }
  return fastest;
}

/// Which guidance rungs a weekly tempo is read from.
sealed class TempoRungPolicy {
  const TempoRungPolicy();
}

/// Every rung in one median. For characterization only: a median over cued and
/// unguided playing together describes neither.
final class PooledRungs extends TempoRungPolicy {
  const PooledRungs();

  @override
  String toString() => 'pooled';
}

/// One rung only.
final class SingleRung extends TempoRungPolicy {
  final int guidanceIndependence;

  const SingleRung(this.guidanceIndependence);

  @override
  String toString() => 'rung $guidanceIndependence';
}

/// Each week, the most independent rung with at least [minimumObservations]
/// counted observations.
final class MostIndependentRung extends TempoRungPolicy {
  final int minimumObservations;

  const MostIndependentRung({required this.minimumObservations})
    : assert(minimumObservations > 0);

  @override
  String toString() => 'most independent, at least $minimumObservations';
}

/// One week of a weekly pace series.
@immutable
class WeeklyTempo {
  /// The Monday the week starts on.
  final CalendarDay week;

  /// The rung the median was read from, or null when none was, or when rungs
  /// were pooled.
  final int? guidanceIndependence;

  /// The median pace, or null when the week has none.
  final double? medianTempoBpm;

  /// How many observations the median was read from.
  final int observations;

  const WeeklyTempo({
    required this.week,
    required this.guidanceIndependence,
    required this.medianTempoBpm,
    required this.observations,
  });

  @override
  String toString() =>
      'WeeklyTempo($week, rung $guidanceIndependence, $medianTempoBpm '
      'from $observations)';
}

/// How fast [hands] has been playing, week by week.
///
/// An observational trend rather than a capability claim: every completed
/// attempt with a measured pace counts, whatever its motor score, at the pace
/// actually played. Each week reads the most independent rung with any
/// observation, so rungs are never pooled, and [WeeklyTempo.observations]
/// carries how little a sparse week rests on.
List<WeeklyTempo> playingPace(
  List<FluencyDay> days, {
  required HandConfiguration hands,
  int octaves = 1,
}) => weeklyTempos(
  days,
  hands: hands,
  policy: const MostIndependentRung(minimumObservations: 1),
  octaves: octaves,
);

/// The median pace for [hands] in each week from the first practiced to the
/// last, weeks without a value included.
///
/// With a [qualification], only its qualifying observations count, at the pace
/// they demonstrate. Without one, every observation counts at the pace played.
/// Parallel motion only, at [octaves]. The median is taken over the week's
/// observations directly, never combined from daily summaries.
List<WeeklyTempo> weeklyTempos(
  List<FluencyDay> days, {
  required HandConfiguration hands,
  required TempoRungPolicy policy,
  TempoQualification? qualification,
  int octaves = 1,
}) {
  if (days.isEmpty) return const [];
  final byWeek = <CalendarDay, List<TempoObservation>>{};
  for (final day in days) {
    byWeek
        .putIfAbsent(day.day.weekStart, () => [])
        .addAll(
          day.tempos.where(
            (observation) =>
                observation.hands == hands &&
                observation.handMotion == HandMotion.parallel &&
                observation.octaves == octaves &&
                (qualification?.qualifies(observation) ?? true),
          ),
        );
  }

  final series = <WeeklyTempo>[];
  final last = days.last.day.weekStart;
  for (
    var week = days.first.day.weekStart;
    week.compareTo(last) <= 0;
    week = week.plusDays(7)
  ) {
    final observations = byWeek[week] ?? const [];
    final rung = switch (policy) {
      PooledRungs() => null,
      SingleRung(:final guidanceIndependence) => guidanceIndependence,
      MostIndependentRung(:final minimumObservations) => _mostIndependent(
        observations,
        minimumObservations,
      ),
    };
    final selected = switch (policy) {
      PooledRungs() => observations,
      _ => [
        for (final observation in observations)
          if (observation.guidanceIndependence == rung) observation,
      ],
    };
    series.add(
      WeeklyTempo(
        week: week,
        guidanceIndependence: selected.isEmpty ? null : rung,
        medianTempoBpm: _median([
          for (final observation in selected)
            qualification?.tempoOf(observation) ?? observation.playedTempoBpm,
        ]),
        observations: selected.length,
      ),
    );
  }
  return series;
}

int? _mostIndependent(List<TempoObservation> observations, int minimum) {
  for (var rung = 2; rung >= 0; rung--) {
    final count = observations
        .where((observation) => observation.guidanceIndependence == rung)
        .length;
    if (count >= minimum) return rung;
  }
  return null;
}

double? _median(List<double> values) {
  if (values.isEmpty) return null;
  values.sort();
  final middle = values.length ~/ 2;
  return values.length.isOdd
      ? values[middle]
      : (values[middle - 1] + values[middle]) / 2;
}
