import 'dart:io';
import 'dart:isolate';

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

class _SchedulerBenchmarkScreenState extends State<SchedulerBenchmarkScreen>
    with SingleTickerProviderStateMixin {
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

    final stalls = _FrameStalls(this)..start();
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
    final worstStall = stalls.stop();

    lines
      ..add('on the UI isolate')
      ..add(
        'case'.padRight(18) +
            'materials'.padLeft(10) +
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
            '${run.catalogMaterials}'.padLeft(10) +
            '${run.generated}'.padLeft(11) +
            '${run.ranked}'.padLeft(8) +
            _ms(run.medianDecide).padLeft(12) +
            _ms(run.p95Decide).padLeft(12) +
            _ms(run.medianWall).padLeft(10) +
            _ms(run.p95Wall).padLeft(10),
      );
    }

    lines
      ..add('')
      ..add(
        'longest gap between frames while the above ran: '
        '${_ms(worstStall)}',
      )
      ..add('')
      ..add('on a worker isolate')
      ..add(
        'case'.padRight(18) +
            'decisions'.padLeft(11) +
            'decide p50'.padLeft(12) +
            'decide p95'.padLeft(12),
      );
    for (final benchmark in _cases) {
      _reportProgress('${benchmark.name}, worker', 0, 1);
      final micros = await Isolate.run(
        () => runSchedulerBenchmarkMicroseconds(
          scopeName: ArpeggioPolicyScope.fullMixed.name,
          playerId: benchmark.player,
          warmupSlots: benchmark.warmup,
          measuredSlots: benchmark.measured,
        ),
      );
      final sorted = micros.toList()..sort();
      lines.add(
        benchmark.name.padRight(18) +
            '${sorted.length}'.padLeft(11) +
            _quantile(sorted, 0.5).padLeft(12) +
            _quantile(sorted, 0.95).padLeft(12),
      );
    }

    return lines.join('\n');
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

/// The longest the interface went without a frame.
///
/// A ticker runs once per frame, so the gap between its callbacks is what a
/// blocked UI isolate looks like from the outside. This is the product number
/// the scheduler timing feeds into: a decision nobody waits for is a different
/// thing from one that holds a tap.
class _FrameStalls {
  final TickerProvider vsync;
  Ticker? _ticker;
  Duration _previous = Duration.zero;
  Duration _worst = Duration.zero;

  _FrameStalls(this.vsync);

  void start() {
    _ticker = vsync.createTicker((elapsed) {
      final gap = elapsed - _previous;
      if (gap > _worst) _worst = gap;
      _previous = elapsed;
    })..start();
  }

  Duration stop() {
    _ticker?.dispose();
    _ticker = null;
    return _worst;
  }
}
