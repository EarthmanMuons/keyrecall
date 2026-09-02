import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'attempt_screen.dart';
import 'attempt_transcript.dart';

/// One cell of the timing matrix: a tempo, a span, and which repetition.
@immutable
class CalibrationCell {
  /// Requested tempo, in beats per minute.
  final double tempoBpm;

  /// How many octaves the traversal spans.
  final int octaves;

  /// Which of the repetitions of this cell, from zero.
  final int repetition;

  const CalibrationCell({
    required this.tempoBpm,
    required this.octaves,
    required this.repetition,
  });

  /// The exercise this cell asks for.
  ///
  /// Everything except tempo and span is held constant, and the guidance rung
  /// supplies the material throughout: this measures how evenly somebody
  /// plays, so it must not also be measuring whether they remembered the
  /// notes.
  Exercise get exercise => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: octaves,
    direction: ScaleDirection.upDown,
    tempoBpm: tempoBpm,
    guidance: GuidanceContext.continuouslyCued,
  );

  /// How this cell reads in a heading.
  String get label =>
      '${tempoBpm.round()} bpm · $octaves octave${octaves == 1 ? '' : 's'}';

  @override
  String toString() => '${tempoBpm.round()}bpm ${octaves}oct';
}

/// The takes to record, in the order they are asked for.
///
/// Tempo varies fastest and repetitions slowest, so the three takes of a cell
/// are spread across the run rather than played back to back. Playing the same
/// thing three times in a row measures how quickly somebody settles into it,
/// which is a different question from the one being asked.
List<CalibrationCell> calibrationPlan({
  List<double> tempi = const [60, 80, 100, 120],
  List<int> spans = const [1, 2],
  int repetitions = 3,
}) => [
  for (var repetition = 0; repetition < repetitions; repetition++)
    for (final octaves in spans)
      for (final tempoBpm in tempi)
        CalibrationCell(
          tempoBpm: tempoBpm,
          octaves: octaves,
          repetition: repetition,
        ),
];

/// What one recorded take is written as.
///
/// The arrivals are the evidence and the statistics are a convenience. Both
/// are kept, because the question these takes exist to settle is partly
/// whether the statistics are computed the right way: an analysis that could
/// only read the numbers this build produced would not be able to tell a
/// different estimator from a different performance.
Map<String, Object?> takeToJson(
  CalibrationCell cell,
  PerformanceTranscript transcript,
  PerformanceMeasurement measurement,
) => {
  'tempo_bpm': cell.tempoBpm,
  'octaves': cell.octaves,
  'repetition': cell.repetition,
  'material': 'C_MAJOR',
  'hands': HandConfiguration.right.id,
  'direction': ScaleDirection.upDown.id,
  'notes': [
    for (final note in transcript.notes)
      {'note': note.midiNote, 'ms': note.timestampMs},
  ],
  'measured': {
    'expected_notes': measurement.expectedNotes,
    'median_interval_ms': measurement.medianIntervalMs,
    'dispersion': measurement.dispersion,
    'temporal_stability': measurement.temporalStability,
    'worst_interval_ratio': measurement.worstIntervalRatio,
    'continuity': measurement.continuity,
    'completed': measurement.completed,
  },
};

/// A run in progress: the plan, and what has been recorded against it.
///
/// Takes sit in plan order with gaps for what is not recorded yet, so redoing
/// one replaces it rather than appending a second copy of the same cell.
@immutable
class CalibrationRun {
  /// Every cell to record, in order.
  final List<CalibrationCell> plan;

  /// What has been recorded, indexed by position in [plan].
  final List<Map<String, Object?>?> takes;

  /// Where the run was last written, once it has been.
  final String? savedTo;

  /// The cell just recorded, so it can be redone at the moment somebody knows
  /// it went badly rather than only from the summary afterwards.
  final int? lastRecorded;

  const CalibrationRun({
    required this.plan,
    required this.takes,
    this.savedTo,
    this.lastRecorded,
  });

  /// How many cells have a take.
  int get recorded => takes.whereType<Map<String, Object?>>().length;

  /// The next cell with no take, or null when the run is complete.
  int? get next {
    for (var index = 0; index < takes.length; index++) {
      if (takes[index] == null) return index;
    }
    return null;
  }

  /// The run as it is written out.
  Map<String, Object?> toJson() => {
    'recorded_at': DateTime.now().toUtc().toIso8601String(),
    'policy': {
      'steady_dispersion': MeasurementPolicy.standard.steadyDispersion,
      'unsteady_dispersion': MeasurementPolicy.standard.unsteadyDispersion,
    },
    'takes': takes.whereType<Map<String, Object?>>().toList(),
  };
}

/// The run, held above the screen so leaving it does not discard the takes.
///
/// A screen is where a run is driven from, not where it lives. Every take is
/// also written to disk as it arrives, because the thing being collected takes
/// twenty minutes at an instrument and a stray back gesture should not be able
/// to cost that.
final calibrationRunProvider =
    NotifierProvider<CalibrationRunNotifier, CalibrationRun>(
      CalibrationRunNotifier.new,
    );

class CalibrationRunNotifier extends Notifier<CalibrationRun> {
  @override
  CalibrationRun build() {
    final plan = calibrationPlan();
    return CalibrationRun(
      plan: plan,
      takes: List<Map<String, Object?>?>.filled(plan.length, null),
    );
  }

  /// Records [take] at [position] and writes the run out.
  Future<void> record(int position, Map<String, Object?> take) async {
    final takes = [...state.takes]..[position] = take;
    state = CalibrationRun(
      plan: state.plan,
      takes: takes,
      savedTo: state.savedTo,
      lastRecorded: position,
    );
    await save();
  }

  /// Forgets the take at [position], so the run asks for it again.
  void redo(int position) {
    final takes = [...state.takes]..[position] = null;
    state = CalibrationRun(
      plan: state.plan,
      takes: takes,
      savedTo: state.savedTo,
    );
  }

  /// Starts over, discarding everything recorded.
  void reset() => state = build();

  /// Writes the run where the Files app and Finder can reach it.
  ///
  /// Documents rather than Application Support, for the reason the onset takes
  /// are: calibration is meant to leave the phone, and practice history is
  /// not. One file per run, rewritten as it grows, so an interrupted run
  /// leaves what it had rather than nothing.
  Future<String> save() async {
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/timing-calibration',
    )..createSync(recursive: true);
    final existing = state.savedTo;
    final path =
        existing ??
        '${directory.path}/'
            '${DateTime.now().toIso8601String().replaceAll(RegExp('[:.]'), '-')}'
            '.json';

    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(state.toJson()),
    );
    if (existing == null) {
      state = CalibrationRun(
        plan: state.plan,
        takes: state.takes,
        savedTo: path,
        lastRecorded: state.lastRecorded,
      );
    }
    return path;
  }
}

/// Records the takes behind the timing constants.
///
/// The constants in [MeasurementPolicy] came from five takes at one tempo and
/// one traversal length, and two questions have since been asked of them that
/// those takes cannot answer. Dispersion is a spread over a median, so the
/// variation it allows shrinks in milliseconds as somebody plays faster, and
/// nothing recorded so far says whether real playing does the same. And the
/// quartile estimator spans a wider fraction of a short traversal than a long
/// one, so exercise length changes what dispersion means before any playing is
/// considered.
///
/// This walks a factorial plan so the two can be told apart: tempo at fixed
/// length, and length at fixed tempo, with repetitions so one ragged take does
/// not read as a pattern. It decides nothing. It plays each cell through the
/// ordinary attempt screen, so what is recorded is what the app really
/// presents, and writes the arrivals beside the statistics for analysis
/// somewhere else.
///
/// See `analysis/timing-calibration/`.
class TimingCalibrationScreen extends ConsumerStatefulWidget {
  const TimingCalibrationScreen({super.key});

  @override
  ConsumerState<TimingCalibrationScreen> createState() =>
      _TimingCalibrationScreenState();
}

class _TimingCalibrationScreenState
    extends ConsumerState<TimingCalibrationScreen> {
  /// Whether a take is on screen, as opposed to the run's own display.
  bool _playing = false;

  Future<void> _finish(int position, CalibrationCell cell) async {
    final capture = ref.read(attemptTranscriptProvider);
    if (capture.isInterrupted) {
      setState(() => _playing = false);
      return;
    }
    final transcript = capture.transcript;
    if (transcript.isNotEmpty) {
      await ref
          .read(calibrationRunProvider.notifier)
          .record(
            position,
            takeToJson(
              cell,
              transcript,
              measure(
                realization: realize(cell.exercise),
                transcript: transcript,
              ),
            ),
          );
    }
    // Straight into the next one. A run is twenty-odd short takes, and
    // choosing each of them from a list is both slower and a way to lose
    // track of which cell was actually just played.
    if (mounted) setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final run = ref.watch(calibrationRunProvider);
    final position = run.next;

    if (_playing && position != null) {
      final cell = run.plan[position];
      return Scaffold(
        appBar: AppBar(
          title: Text('${run.recorded + 1} of ${run.plan.length}'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(24),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(cell.label, textAlign: TextAlign.center),
            ),
          ),
        ),
        body: AttemptView(
          key: ValueKey(position),
          exercise: cell.exercise,
          onFinish: (_) => _finish(position, cell),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timing calibration'),
        actions: [
          if (run.recorded > 0)
            IconButton(
              tooltip: 'Start over',
              onPressed: () =>
                  ref.read(calibrationRunProvider.notifier).reset(),
              icon: const Icon(Icons.restart_alt),
            ),
        ],
      ),
      body: position == null
          ? _Finished(run: run)
          : _UpNext(
              run: run,
              position: position,
              onPlay: () => setState(() => _playing = true),
            ),
    );
  }
}

/// What the run is asking for next.
class _UpNext extends ConsumerWidget {
  const _UpNext({
    required this.run,
    required this.position,
    required this.onPlay,
  });

  final CalibrationRun run;
  final int position;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cell = run.plan[position];
    final saved = run.savedTo;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            'Take ${run.recorded + 1} of ${run.plan.length}',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            cell.label,
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'As evenly as you can, at the tempo it asks for. The notes stay '
            'up, so this is only about how it sits in time.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (saved != null) ...[
            const SizedBox(height: 16),
            Text(
              'Saved as you go, so leaving keeps what you have.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const Spacer(),
          // Offered here rather than only at the end, because this is the
          // moment somebody knows a take was ragged: they have just played it.
          // Waiting for the summary asks them to remember which of
          // twenty-four it was.
          if (run.lastRecorded case final last?) ...[
            _JustRecorded(run: run, position: last),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 88,
            child: FilledButton(
              onPressed: onPlay,
              style: FilledButton.styleFrom(
                textStyle: theme.textTheme.headlineSmall,
              ),
              child: Text(run.recorded == 0 ? 'Start' : 'Next take'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The take just played, and the offer to do it again.
///
/// Its dispersion is shown because that is the number the run exists to
/// collect: a take somebody felt was ragged and that measured ragged is
/// evidence, and one that felt fine and measured ragged is the interesting
/// case rather than a take to throw away.
class _JustRecorded extends ConsumerWidget {
  const _JustRecorded({required this.run, required this.position});

  final CalibrationRun run;
  final int position;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cell = run.plan[position];
    final measured = run.takes[position]?['measured'] as Map<String, Object?>?;
    final dispersion = measured?['dispersion'] as double?;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            'Just played ${cell.label}'
            '${dispersion == null ? '' : ', dispersion '
                      '${dispersion.toStringAsFixed(3)}'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () =>
              ref.read(calibrationRunProvider.notifier).redo(position),
          child: const Text('Redo it'),
        ),
      ],
    );
  }
}

/// The run, once every cell has a take.
///
/// Dispersion is shown per cell because that is what makes a ragged take
/// visible after the fact: somebody who knows one of these went badly can
/// redo exactly that one rather than the whole run.
class _Finished extends ConsumerWidget {
  const _Finished({required this.run});

  final CalibrationRun run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'All ${run.plan.length} recorded.',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              if (run.savedTo case final path?) ...[
                const SizedBox(height: 8),
                Text(
                  path.split('/').last,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: jsonEncode(run.toJson())),
                      ),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        final path = await ref
                            .read(calibrationRunProvider.notifier)
                            .save();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('saved ${path.split('/').last}'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: run.plan.length,
            itemBuilder: (context, index) {
              final cell = run.plan[index];
              final measured =
                  run.takes[index]?['measured'] as Map<String, Object?>?;
              final dispersion = measured?['dispersion'] as double?;
              return ListTile(
                dense: true,
                title: Text('${cell.label}, take ${cell.repetition + 1}'),
                subtitle: Text(
                  dispersion == null
                      ? 'nothing to time'
                      : 'dispersion ${dispersion.toStringAsFixed(3)}',
                ),
                trailing: TextButton(
                  onPressed: () =>
                      ref.read(calibrationRunProvider.notifier).redo(index),
                  child: const Text('Redo'),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
