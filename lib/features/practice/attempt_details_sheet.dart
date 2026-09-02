import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'attempt_detail_trace.dart';

Future<void> showAttemptDetails(
  BuildContext context, {
  required Exercise exercise,
  required AttemptDetailTrace trace,
  required double achievedTempoBpm,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => AttemptDetailsSheet(
    exercise: exercise,
    trace: trace,
    achievedTempoBpm: achievedTempoBpm,
  ),
);

class AttemptDetailsSheet extends StatelessWidget {
  const AttemptDetailsSheet({
    required this.exercise,
    required this.trace,
    required this.achievedTempoBpm,
    super.key,
  });

  final Exercise exercise;
  final AttemptDetailTrace trace;
  final double achievedTempoBpm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: layout.readableWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Attempt details', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Where things happened in this run.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                _NotesDetail(trace: trace, exercise: exercise),
                const SizedBox(height: 28),
                _FlowDetail(trace: trace, exercise: exercise),
                if (trace.pulse.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _TraceSection(
                    title: 'Pulse',
                    explanation:
                        "Each interval's distance from this run's pulse.",
                    points: trace.pulse,
                    momentCount: trace.momentCount,
                    direction: exercise.conditions.direction,
                    upperLabel: 'early',
                    centerLabel: 'on pulse',
                    lowerLabel: 'late',
                  ),
                ],
                if (trace.coordination.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  _TraceSection(
                    title: 'Coordination',
                    explanation: 'How far apart the hands arrived.',
                    points: trace.coordination,
                    momentCount: trace.momentCount,
                    direction: exercise.conditions.direction,
                    upperLabel: 'RH early',
                    centerLabel: 'together',
                    lowerLabel: 'LH early',
                  ),
                ],
                const SizedBox(height: 28),
                Text('Tempo', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '${achievedTempoBpm.round()} BPM overall · target '
                  '${exercise.conditions.tempoBpm.round()}',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesDetail extends StatelessWidget {
  const _NotesDetail({required this.trace, required this.exercise});

  final AttemptDetailTrace trace;
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final departures = trace.notes
        .where((status) => status == NoteMomentStatus.departed)
        .length;
    final missing = trace.notes
        .where((status) => status == NoteMomentStatus.missing)
        .length;
    final summary = [
      if (departures > 0) '$departures changed',
      if (missing > 0) '$missing missing',
      if (trace.extraNotes > 0) '${trace.extraNotes} extra',
    ].join(' · ');
    return Semantics(
      label: summary.isEmpty ? 'Notes: all matched' : 'Notes: $summary',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              summary.isEmpty ? 'All notes matched.' : summary,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            SizedBox(height: 24, child: _NoteStrip(trace)),
            const SizedBox(height: 6),
            _TraversalLabels(direction: exercise.conditions.direction),
          ],
        ),
      ),
    );
  }
}

class _NoteStrip extends StatelessWidget {
  const _NoteStrip(this.trace);

  final AttemptDetailTrace trace;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(height: 2, color: colors.outlineVariant),
          for (final (index, status) in trace.notes.indexed)
            Positioned(
              left: _xFor(index, trace.momentCount, constraints.maxWidth) - 5,
              child: _NoteMarker(status),
            ),
          for (final position in trace.extraNotePositions)
            Positioned(
              left:
                  _xFor(position, trace.momentCount, constraints.maxWidth) - 7,
              child: Icon(Icons.close, size: 14, color: colors.error),
            ),
        ],
      ),
    );
  }
}

class _NoteMarker extends StatelessWidget {
  const _NoteMarker(this.status);

  final NoteMomentStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (status) {
          NoteMomentStatus.matched => colors.primary,
          NoteMomentStatus.departed => colors.error,
          NoteMomentStatus.missing => colors.surface,
        },
        border: status == NoteMomentStatus.missing
            ? Border.all(color: colors.error, width: 2)
            : null,
      ),
    );
  }
}

class _FlowDetail extends StatelessWidget {
  const _FlowDetail({required this.trace, required this.exercise});

  final AttemptDetailTrace trace;
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gap = trace.flowGap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Flow', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          gap == null
              ? 'No pronounced break.'
              : 'Longest break · ${(gap.durationMs / 1000).toStringAsFixed(1)} s',
          style: theme.textTheme.bodyMedium,
        ),
        if (gap != null) ...[
          const SizedBox(height: 14),
          _PositionStrip(
            position: gap.beforePosition.toDouble(),
            momentCount: trace.momentCount,
          ),
          const SizedBox(height: 6),
          _TraversalLabels(direction: exercise.conditions.direction),
        ],
      ],
    );
  }
}

class _PositionStrip extends StatelessWidget {
  const _PositionStrip({required this.position, required this.momentCount});

  final double position;
  final int momentCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 14,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.center,
          children: [
            Container(height: 2, color: colors.outlineVariant),
            Positioned(
              left: _xFor(position, momentCount, constraints.maxWidth) - 5,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TraceSection extends StatelessWidget {
  const _TraceSection({
    required this.title,
    required this.explanation,
    required this.points,
    required this.momentCount,
    required this.direction,
    required this.upperLabel,
    required this.centerLabel,
    required this.lowerLabel,
  });

  final String title;
  final String explanation;
  final List<AttemptTracePoint> points;
  final int momentCount;
  final ScaleDirection direction;
  final String upperLabel;
  final String centerLabel;
  final String lowerLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final range = math.max(
      40.0,
      points.map((point) => point.value.abs()).reduce(math.max) * 1.15,
    );
    final upper = math.max(
      0,
      points.map((point) => point.value).reduce(math.max),
    );
    final lower = math.max(
      0,
      -points.map((point) => point.value).reduce(math.min),
    );
    return Semantics(
      label:
          '$title trace. Farthest $upperLabel ${upper.round()} milliseconds; '
          'farthest $lowerLabel ${lower.round()} milliseconds.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(explanation, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(upperLabel, style: theme.textTheme.labelSmall),
                        Text(centerLabel, style: theme.textTheme.labelSmall),
                        Text(lowerLabel, style: theme.textTheme.labelSmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: math.max(1, momentCount - 1).toDouble(),
                        minY: -range,
                        maxY: range,
                        clipData: const FlClipData.all(),
                        lineTouchData: const LineTouchData(enabled: false),
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        extraLinesData: ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: 0,
                              color: theme.colorScheme.outlineVariant,
                              strokeWidth: 1,
                            ),
                          ],
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (final point in points)
                                FlSpot(point.position.toDouble(), point.value),
                            ],
                            isCurved: false,
                            color: theme.colorScheme.primary,
                            barWidth: 2,
                            dotData: FlDotData(
                              getDotPainter: (spot, percent, barData, index) =>
                                  FlDotCirclePainter(
                                    radius: 3,
                                    color: theme.colorScheme.primary,
                                    strokeWidth: 0,
                                  ),
                            ),
                            belowBarData: BarAreaData(show: false),
                          ),
                        ],
                      ),
                      duration: Duration.zero,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 72),
              child: _TraversalLabels(direction: direction),
            ),
          ],
        ),
      ),
    );
  }
}

class _TraversalLabels extends StatelessWidget {
  const _TraversalLabels({required this.direction});

  final ScaleDirection direction;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: switch (direction) {
        ScaleDirection.up => [
          Text('start', style: style),
          Text('top', style: style),
        ],
        ScaleDirection.upDown => [
          Text('up', style: style),
          Text('turn', style: style),
          Text('down', style: style),
        ],
      },
    );
  }
}

double _xFor(num position, int momentCount, double width) {
  if (momentCount <= 1) return width / 2;
  return position / (momentCount - 1) * width;
}
