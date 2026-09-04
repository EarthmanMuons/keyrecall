import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:keyrecall_simulation/keyrecall_simulation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

/// What a scheduling decision costs on this device, in a release build.
///
/// Temporary. Desktop profiling took the production-scale decision from about
/// 200 ms to about 82 ms without changing any decision, and the remaining cost
/// is mostly the price of ranking alternatives a mature learner can genuinely
/// be offered. Whether that is a problem is a question about hardware and about
/// where the decision sits in a transition, which only a device can answer.
class SchedulerBenchmarkScreen extends StatefulWidget {
  const SchedulerBenchmarkScreen({super.key});

  @override
  State<SchedulerBenchmarkScreen> createState() =>
      _SchedulerBenchmarkScreenState();
}

class _SchedulerBenchmarkScreenState extends State<SchedulerBenchmarkScreen> {
  static const _cases = [
    (name: 'cold, weak', player: 'true_beginner', warmup: 0, measured: 1),
    (name: 'steady, weak', player: 'true_beginner', warmup: 40, measured: 20),
    (name: 'mature, advanced', player: 'advanced', warmup: 80, measured: 20),
  ];

  bool _running = false;
  String _progress = '';
  String? _report;
  String? _path;
  Object? _error;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scheduler benchmark')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Drives the full mixed catalog, 48 scales and 24 arpeggios, through '
          'the real session and scheduler. Each case warms up to the state '
          'whose decisions are expensive, then measures the ones after it.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'The interface freezes while a case runs on the UI isolate. That is '
          'the measurement.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _running ? null : _run,
          icon: const Icon(Icons.speed),
          label: Text(_running ? 'Running' : 'Run benchmark'),
        ),
        if (_progress.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(_progress),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            '$_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (_path != null) ...[
          const SizedBox(height: 16),
          Text('saved ${_path!}'),
        ],
        if (_report != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                _report!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ],
      ],
    ),
  );

  Future<void> _run() async {
    setState(() {
      _running = true;
      _report = null;
      _path = null;
      _error = null;
      _progress = 'starting';
    });
    try {
      final report = await _measure();
      final path = await _write(report);
      if (!mounted) return;
      setState(() {
        _report = report;
        _path = path;
        _progress = 'done';
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<String> _measure() async {
    final lines = <String>[
      'scheduler decision benchmark',
      'platform  ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}',
      'build     ${kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug'}',
      'recorded  ${DateTime.now().toIso8601String()}',
      '',
    ];

    final onIsolate = <String, SchedulerBenchmarkRun>{};
    for (final benchmark in _cases) {
      onIsolate[benchmark.name] = await runSchedulerBenchmark(
        caseName: benchmark.name,
        scope: ArpeggioPolicyScope.fullMixed,
        player: PlayerArchetypes.all.firstWhere(
          (archetype) => archetype.id == benchmark.player,
        ),
        warmupSlots: benchmark.warmup,
        measuredSlots: benchmark.measured,
        onProgress: (completed, total) =>
            _reportProgress(benchmark.name, completed, total),
      );
    }

    lines
      ..add('on the UI isolate')
      ..add(
        'case'.padRight(18) +
            'decisions'.padLeft(11) +
            'generated'.padLeft(11) +
            'ranked'.padLeft(8) +
            'decide p50'.padLeft(12) +
            'decide p95'.padLeft(12) +
            'slot p50'.padLeft(10) +
            'slot p95'.padLeft(10),
      );
    for (final benchmark in _cases) {
      final run = onIsolate[benchmark.name]!;
      lines.add(
        run.caseName.padRight(18) +
            '${run.decisions.length}'.padLeft(11) +
            '${run.generated}'.padLeft(11) +
            '${run.ranked}'.padLeft(8) +
            _ms(run.medianDecide).padLeft(12) +
            _spread(run, _ms(run.p95Decide)).padLeft(12) +
            _ms(run.medianWall).padLeft(10) +
            _spread(run, _ms(run.p95Wall)).padLeft(10),
      );
    }

    lines
      ..add('')
      ..add('frames while one decision runs')
      ..add(
        'case'.padRight(18) +
            'placement'.padRight(10) +
            'worst gap'.padLeft(12) +
            'frames'.padLeft(8),
      );
    for (final benchmark in _cases.where((one) => one.warmup > 0)) {
      _reportProgress('${benchmark.name}, frames', 0, 1);
      final session = await _matureSession(benchmark);
      final observed = await _framesDuring(session.step);
      lines.add(
        benchmark.name.padRight(18) +
            'ui'.padRight(10) +
            _ms(observed.worst).padLeft(12) +
            '${observed.frames}'.padLeft(8),
      );
    }

    await _measureOwningWorker(lines);

    lines
      ..add('')
      ..add('scope rebuilt on a worker isolate per case')
      ..add(
        'case'.padRight(18) +
            'decisions'.padLeft(11) +
            'decide p50'.padLeft(12) +
            'decide p95'.padLeft(12),
      );
    for (final benchmark in _cases) {
      _reportProgress('${benchmark.name}, worker', 0, 1);
      // Per case, so one failure costs its own row rather than the run: the
      // measured cases above are expensive to reach and worth keeping.
      try {
        final sorted = (await runSchedulerBenchmarkOnWorker(
          scopeName: ArpeggioPolicyScope.fullMixed.name,
          playerId: benchmark.player,
          warmupSlots: benchmark.warmup,
          measuredSlots: benchmark.measured,
        )).toList()..sort();
        lines.add(
          benchmark.name.padRight(18) +
              '${sorted.length}'.padLeft(11) +
              _quantile(sorted, 0.5).padLeft(12) +
              _quantile(sorted, 0.95).padLeft(12),
        );
      } on Object catch (error) {
        lines.add('${benchmark.name.padRight(18)}failed: $error');
      }
    }

    return lines.join('\n');
  }

  /// The production message shape: a worker that resolved the scope once, and
  /// a slot that sends it the state to decide from.
  Future<void> _measureOwningWorker(List<String> lines) async {
    final mature = _cases.last;
    final session = await _matureSession(mature);
    final worker = await SchedulerWorker.start(
      ArpeggioPolicyScope.fullMixed.name,
    );
    try {
      final roundTrips = <int>[];
      for (var trip = 0; trip < mature.measured; trip++) {
        final watch = Stopwatch()..start();
        await worker.decide(
          state: session.learnerState,
          session: session.sessionState,
          at: session.nextAt,
        );
        roundTrips.add(watch.elapsedMicroseconds);
      }
      roundTrips.sort();
      final observed = await _framesDuring(
        () => worker.decide(
          state: session.learnerState,
          session: session.sessionState,
          at: session.nextAt,
        ),
      );
      lines
        ..add(
          mature.name.padRight(18) +
              'worker'.padRight(10) +
              _ms(observed.worst).padLeft(12) +
              '${observed.frames}'.padLeft(8),
        )
        ..add('')
        ..add('a worker that owns the scope, at the mature state')
        ..add(
          'round trips'.padRight(18) + 'p50'.padLeft(12) + 'p95'.padLeft(12),
        )
        ..add(
          '${roundTrips.length}'.padRight(18) +
              _quantile(roundTrips, 0.5).padLeft(12) +
              _quantile(roundTrips, 0.95).padLeft(12),
        );
    } finally {
      worker.stop();
    }
  }

  Future<BenchmarkSession> _matureSession(
    ({String name, String player, int warmup, int measured}) benchmark,
  ) {
    _reportProgress('${benchmark.name}, warming', 0, benchmark.warmup);
    return openBenchmarkSession(
      scope: ArpeggioPolicyScope.fullMixed,
      player: PlayerArchetypes.all.firstWhere(
        (archetype) => archetype.id == benchmark.player,
      ),
      warmupSlots: benchmark.warmup,
      onProgress: (completed, total) =>
          _reportProgress('${benchmark.name}, warming', completed, total),
    );
  }

  void _reportProgress(String name, int completed, int total) {
    if (!mounted) return;
    if (completed % 10 != 0 && completed != total) return;
    setState(() => _progress = '$name  $completed/$total');
  }

  Future<String> _write(String report) async {
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/benchmarks',
    )..createSync(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final file = File('${directory.path}/$stamp-scheduler.txt')
      ..writeAsStringSync(report);
    return file.path;
  }

  /// A p95 over one observation is that observation, so it is not reported.
  static String _spread(SchedulerBenchmarkRun run, String value) =>
      run.decisions.length < 2 ? '-' : value;

  static String _ms(Duration duration) =>
      '${(duration.inMicroseconds / 1000).toStringAsFixed(1)} ms';

  static String _quantile(List<int> sorted, double probability) =>
      sorted.isEmpty
      ? '-'
      : _ms(
          Duration(
            microseconds: sorted[((sorted.length - 1) * probability).round()],
          ),
        );
}

/// What the interface manages while one decision runs.
///
/// The worst interval between consecutive frames, and how many frames happened
/// at all. Measuring to the next frame after the work finishes cannot tell the
/// two placements apart, because it counts the wait itself whether or not the
/// isolate was free to draw during it. Asking for frames throughout can: a
/// blocked isolate produces one long interval and almost no frames, and a free
/// one keeps drawing while it waits.
Future<({Duration worst, int frames})> _framesDuring(
  Future<void> Function() work,
) async {
  final binding = SchedulerBinding.instance;
  final watch = Stopwatch()..start();
  var previous = Duration.zero;
  var worst = Duration.zero;
  var frames = 0;
  var running = true;

  void observe(Duration _) {
    final now = watch.elapsed;
    final gap = now - previous;
    if (gap > worst) worst = gap;
    previous = now;
    frames++;
    if (running) {
      binding
        ..addPostFrameCallback(observe)
        ..scheduleFrame();
    }
  }

  binding
    ..addPostFrameCallback(observe)
    ..scheduleFrame();
  await work();
  running = false;

  final closed = Completer<void>();
  binding
    ..addPostFrameCallback((_) {
      final gap = watch.elapsed - previous;
      if (gap > worst) worst = gap;
      closed.complete();
    })
    ..scheduleFrame();
  await closed.future;
  return (worst: worst, frames: frames);
}
