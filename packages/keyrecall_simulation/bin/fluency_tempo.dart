import 'dart:io';
import 'dart:isolate';

import 'package:args/args.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// What each candidate rule for the tempo trend chart would show a learner,
/// week by week, over histories the production loop produced.
///
/// The question is whether reading only unguided playing leaves the chart empty
/// for weeks, and whether picking each week's most independent rung with enough
/// evidence fills it without mixing rungs into one median. So every rule is
/// read from the same histories, and each cell reports how often a value exists
/// as well as what it is.
Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('seeds', defaultsTo: '12')
    ..addOption('weeks', defaultsTo: '8')
    ..addOption('sittings', defaultsTo: '3', help: 'sittings a week')
    ..addOption('slots', defaultsTo: '20', help: 'attempts a sitting')
    ..addOption('minimum', defaultsTo: '3', help: 'evidence for a rung')
    ..addMultiOption(
      'archetypes',
      defaultsTo: [
        'true_beginner',
        'developing',
        'intermediate',
        'uneven_hands',
      ],
    )
    ..addFlag('help', negatable: false);
  final options = parser.parse(arguments);
  if (options.flag('help')) {
    stdout.writeln(parser.usage);
    return;
  }
  final plan = _Plan(
    weeks: int.parse(options.option('weeks')!),
    sittingsPerWeek: int.parse(options.option('sittings')!),
    slots: int.parse(options.option('slots')!),
    minimum: int.parse(options.option('minimum')!),
  );
  final seeds = int.parse(options.option('seeds')!);
  final players = [
    for (final id in options.multiOption('archetypes'))
      PlayerArchetypes.all.firstWhere(
        (player) => player.id == id,
        orElse: () => throw ArgumentError.value(id, 'archetypes'),
      ),
  ];

  final stopwatch = Stopwatch()..start();
  final buckets = dealTrajectoryJobs(seeds, players: players);
  final batches = await Future.wait([
    for (final bucket in buckets)
      Isolate.run(
        () => Future.wait([for (final job in bucket) _run(job, plan)]),
      ),
  ]);
  final runs = batches.expand((batch) => batch).toList();

  stdout.writeln(
    'weekly tempo by rule, $seeds seeds, ${plan.weeks} weeks x '
    '${plan.sittingsPerWeek} sittings x ${plan.slots} slots, '
    'in ${stopwatch.elapsed.inSeconds}s\n'
    '  cell = share of seeds with a value, mean median bpm, mean observations\n'
    '  pooled mixes rungs; unguided reads rung 2; best reads the most '
    'independent rung with >= ${plan.minimum}, shown with its rung mix;\n'
    '  playing reads every completed attempt with a pace, unqualified\n',
  );

  for (final player in players) {
    final mine = [
      for (final run in runs)
        if (run.archetype == player.id) run,
    ];
    stdout.writeln('== ${player.id}');
    for (final hands in HandConfiguration.values) {
      stdout.writeln(
        '  ${hands.id.toLowerCase()}\n'
        '  ${'week'.padRight(6)}${'pooled'.padRight(20)}'
        '${'unguided'.padRight(20)}${'best'.padRight(20)}'
        '${'playing'.padRight(20)}rungs 2/1/0',
      );
      for (var week = 0; week < plan.weeks; week++) {
        String cell(String rule) {
          final values = [
            for (final run in mine) run.series[(rule, hands)]![week],
          ];
          final present = values.where((value) => value.medianTempoBpm != null);
          if (present.isEmpty) return '  0%'.padRight(20);
          final share = (100 * present.length / values.length).round();
          final median =
              present
                  .map((value) => value.medianTempoBpm!)
                  .reduce((a, b) => a + b) /
              present.length;
          final count =
              present
                  .map((value) => value.observations)
                  .reduce((a, b) => a + b) /
              present.length;
          return '${'$share%'.padLeft(4)} ${median.toStringAsFixed(0).padLeft(4)} '
                  'n=${count.toStringAsFixed(1)}'
              .padRight(20);
        }

        final rungs = [2, 1, 0].map(
          (rung) => [
            for (final run in mine)
              if (run.series[('best', hands)]![week].guidanceIndependence ==
                  rung)
                run,
          ].length,
        );
        stdout.writeln(
          '  ${'${week + 1}'.padRight(6)}${cell('pooled')}${cell('unguided')}'
          '${cell('best')}${cell('playing')}${rungs.join('/')}',
        );
      }
    }
    for (final hands in HandConfiguration.values) {
      final total = mine.fold(0, (sum, run) => sum + run.observed[hands]!.$1);
      final qualified = mine.fold(
        0,
        (sum, run) => sum + run.observed[hands]!.$2,
      );
      stdout.writeln(
        '  ${hands.id.toLowerCase()} observations per seed: '
        '${(total / mine.length).toStringAsFixed(1)}, qualifying '
        '${(qualified / mine.length).toStringAsFixed(1)}',
      );
    }
    final contexts = mine.map((run) => run.demonstratedContexts);
    final unguided = mine.map((run) => run.unguidedContexts);
    stdout.writeln(
      '  one-octave material/hands with a demonstrated tempo at the end: '
      'any rung ${_mean(contexts)}, unguided ${_mean(unguided)}\n',
    );
  }
}

class _Plan {
  final int weeks;
  final int sittingsPerWeek;
  final int slots;
  final int minimum;

  const _Plan({
    required this.weeks,
    required this.sittingsPerWeek,
    required this.slots,
    required this.minimum,
  });
}

class _Run {
  final String archetype;
  final Map<(String, HandConfiguration), List<WeeklyTempo>> series;
  final int demonstratedContexts;
  final int unguidedContexts;

  /// One-octave parallel observations by hands, and how many qualified.
  final Map<HandConfiguration, (int, int)> observed;

  const _Run({
    required this.observed,
    required this.archetype,
    required this.series,
    required this.demonstratedContexts,
    required this.unguidedContexts,
  });
}

/// The first Monday of 2026.
final DateTime _start = DateTime.utc(2026, 1, 5, 18);

Future<_Run> _run(TrajectoryJob job, _Plan plan) async {
  final player = PlayerArchetypes.all.firstWhere(
    (player) => player.id == job.archetypeId,
  );
  final profile = Profile(
    id: 'fluency-${player.id}-${job.seed}',
    displayName: player.id,
    createdAt: _start,
    placement: player.placement,
  );
  final store = InMemoryPracticeStore(createdAt: _start);
  final playing = player.begin();
  final random = PythonCompatibleRandom(job.seed);
  var ids = 0;

  for (var week = 0; week < plan.weeks; week++) {
    for (var sitting = 0; sitting < plan.sittingsPerWeek; sitting++) {
      final day = week * 7 + sitting * (7 ~/ plan.sittingsPerWeek);
      final session = await PracticeSession.open(
        store: store,
        profile: profile,
        materials: v1ScaleCatalog,
        sessionId: 'sitting-$week-$sitting',
        nextId: () => '${profile.id}-${ids++}',
      );
      final begins = _start.add(Duration(days: day));
      for (var slot = 0; slot < plan.slots; slot++) {
        final at = begins.add(Duration(minutes: slot));
        switch (await session.decideOutcome(at: at)) {
          case PresentedAttempt(:final exercise, :final decision):
            await session.acknowledgePresentation(decision.attemptId);
            await session.closeWithOutcome(
              playing.play(exercise, random),
              observedWallTime: at,
            );
          case PresentedAcquisition(:final task):
            await session.closeAcquisition(
              performAcquisition(state: playing, task: task, rng: random),
              at: at,
            );
          case PracticeCaughtUp():
          case PracticeBlocked():
          case PracticeSuperseded():
          case PracticeInvalidScope():
        }
      }
    }
  }

  final journal = await store.loadJournal(profile.id);
  final days = FluencyHistory.rebuild(
    journal,
    partition: DayPartition.utc,
  ).days;
  final rules = <String, TempoRungPolicy>{
    'pooled': const PooledRungs(),
    'unguided': const SingleRung(2),
    'best': MostIndependentRung(minimumObservations: plan.minimum),
  };
  final series = {
    for (final MapEntry(key: rule, value: policy) in rules.entries)
      for (final hands in HandConfiguration.values)
        (rule, hands): _padded(
          weeklyTempos(
            days,
            hands: hands,
            policy: policy,
            qualification: TempoQualification.v1,
          ),
          plan.weeks,
        ),
    for (final hands in HandConfiguration.values)
      ('playing', hands): _padded(playingPace(days, hands: hands), plan.weeks),
  };
  final tempos = demonstratedTempos(days).keys.where(
    (context) =>
        context.octaves == 1 && context.handMotion == HandMotion.parallel,
  );
  Set<(String, HandConfiguration)> contextsOf(Iterable<TempoContext> of) => {
    for (final context in of) (context.materialId, context.hands),
  };
  final observations = days
      .expand((day) => day.tempos)
      .where(
        (observation) =>
            observation.octaves == 1 &&
            observation.handMotion == HandMotion.parallel,
      );
  return _Run(
    observed: {
      for (final hands in HandConfiguration.values)
        hands: (
          observations
              .where((observation) => observation.hands == hands)
              .length,
          observations
              .where(
                (observation) =>
                    observation.hands == hands &&
                    TempoQualification.v1.qualifies(observation),
              )
              .length,
        ),
    },
    archetype: player.id,
    series: series,
    demonstratedContexts: contextsOf(tempos).length,
    unguidedContexts: contextsOf(
      tempos.where((context) => context.guidanceIndependence == 2),
    ).length,
  );
}

/// [series] aligned to the plan's weeks from its first Monday.
List<WeeklyTempo> _padded(List<WeeklyTempo> series, int weeks) {
  final first = CalendarDay(_start.year, _start.month, _start.day);
  final byWeek = {for (final week in series) week.week: week};
  return [
    for (var week = 0; week < weeks; week++)
      byWeek[first.plusDays(7 * week)] ??
          WeeklyTempo(
            week: first.plusDays(7 * week),
            guidanceIndependence: null,
            medianTempoBpm: null,
            observations: 0,
          ),
  ];
}

String _mean(Iterable<int> values) => values.isEmpty
    ? '-'
    : (values.reduce((a, b) => a + b) / values.length).toStringAsFixed(1);
