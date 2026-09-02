import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'attempt_diagnosis.dart';
import 'attempt_detail_trace.dart';

const double _minimumTraceHorizontalPadding = 0.15;
const double _traceHorizontalPaddingFraction = 0.015;

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
                    explanation: "How early or late the spacing between notes fell around this run's pulse.",
                    points: trace.pulse,
                    momentCount: trace.momentCount,
                    direction: exercise.conditions.direction,
                    upperLabel: 'early',
                    centerLabel: 'on pulse',
                    lowerLabel: 'late',
                    showsLargestDeviation: true,
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
    final departures = trace.noteDepartures
        .where((departure) => departure.kind == NoteDepartureKind.changed)
        .length;
    final missing = trace.noteDepartures
        .where((departure) => departure.kind == NoteDepartureKind.missing)
        .length;
    final summary = [
      if (departures > 0) '$departures changed',
      if (missing > 0) '$missing missing',
      if (trace.extraNotes > 0) '${trace.extraNotes} extra',
    ].join(' · ');
    final realization = realize(exercise);
    final departureLines = _departureLines(trace.noteDepartures, realization);
    final semantics = [
      summary.isEmpty ? 'Notes: all matched' : 'Notes: $summary',
      ...departureLines,
    ].join('. ');
    return Semantics(
      label: semantics,
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
            if (departureLines.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final line in departureLines) Text(line),
            ],
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
          for (final departure in trace.noteDepartures)
            if (departure.kind == NoteDepartureKind.extra)
              Positioned(
                left:
                    _xFor(
                      departure.position,
                      trace.momentCount,
                      constraints.maxWidth,
                    ) -
                    7,
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
    final realization = realize(exercise);
    final gapDescription = gap == null
        ? 'No pronounced break.'
        : 'Longest break · ${_durationText(gap.durationMs)} '
              'before ${_momentLabel(realization, gap.beforePosition)} '
              '${landmarkAt(gap.beforePosition, realization).phrase}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Flow', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(gapDescription, style: theme.textTheme.bodyMedium),
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
    this.showsLargestDeviation = false,
  });

  final String title;
  final String explanation;
  final List<AttemptTracePoint> points;
  final int momentCount;
  final ScaleDirection direction;
  final String upperLabel;
  final String centerLabel;
  final String lowerLabel;
  final bool showsLargestDeviation;

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
    final description = showsLargestDeviation
        ? '$explanation Largest deviation: '
              '${_durationText(math.max(upper, lower))}.'
        : explanation;
    final lastPosition = math.max(1, momentCount - 1).toDouble();
    final horizontalPadding = math.max(
      _minimumTraceHorizontalPadding,
      lastPosition * _traceHorizontalPaddingFraction,
    );
    final turnPosition = direction == ScaleDirection.upDown
        ? (momentCount - 1) / 2
        : null;
    return Semantics(
      label:
          '$title trace. Farthest $upperLabel ${_spokenDuration(upper)}; '
          'farthest $lowerLabel ${_spokenDuration(lower)}.',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description, style: theme.textTheme.bodyMedium),
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
                        minX: -horizontalPadding,
                        maxX: lastPosition + horizontalPadding,
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
                          verticalLines: [
                            if (turnPosition != null)
                              VerticalLine(
                                x: turnPosition,
                                color: theme.colorScheme.outlineVariant
                                    .withValues(alpha: 0.65),
                                strokeWidth: 1,
                                dashArray: const [4, 4],
                              ),
                          ],
                        ),
                        lineBarsData: [
                          for (final segment in _contiguousSegments(points))
                            LineChartBarData(
                              spots: [
                                for (final point in segment)
                                  FlSpot(
                                    point.position.toDouble(),
                                    point.value,
                                  ),
                              ],
                              isCurved: false,
                              color: theme.colorScheme.primary,
                              barWidth: 2,
                              dotData: FlDotData(
                                getDotPainter:
                                    (spot, percent, barData, index) =>
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

/// A duration as a musician would say it rather than as it was measured.
String _durationText(num ms) => ms.abs() < 1000
    ? '${ms.round()} ms'
    : '${(ms / 1000).toStringAsFixed(1)} s';

String _spokenDuration(num ms) => ms.abs() < 1000
    ? '${ms.round()} milliseconds'
    : '${(ms / 1000).toStringAsFixed(1)} seconds';

double _xFor(num position, int momentCount, double width) {
  if (momentCount <= 1) return width / 2;
  return position / (momentCount - 1) * width;
}

List<List<AttemptTracePoint>> _contiguousSegments(
  List<AttemptTracePoint> points,
) {
  final segments = <List<AttemptTracePoint>>[];
  for (final point in points) {
    if (segments.isEmpty || point.position != segments.last.last.position + 1) {
      segments.add([point]);
    } else {
      segments.last.add(point);
    }
  }
  return segments;
}

List<String> _departureLines(
  List<NoteDeparture> departures,
  ExerciseRealization realization,
) {
  final lines = <String>[];
  for (final kind in NoteDepartureKind.values) {
    final located = [
      for (final departure in departures)
        if (departure.kind == kind) _departureLocator(departure, realization),
    ];
    if (located.isNotEmpty) {
      final label = switch (kind) {
        NoteDepartureKind.changed => 'Changed',
        NoteDepartureKind.missing => 'Missing',
        NoteDepartureKind.extra => 'Extra',
      };
      lines.add('$label: ${located.join(', ')}');
    }
  }
  return lines;
}

String _departureLocator(
  NoteDeparture departure,
  ExerciseRealization realization,
) {
  if (departure.kind != NoteDepartureKind.extra) {
    final position = departure.position.round();
    return '${departure.noteLabel} ${landmarkAt(position, realization).phrase}';
  }

  final before = departure.beforePosition;
  final after = departure.afterPosition;
  if (before != null && after != null && before != after) {
    return '${departure.noteLabel} between '
        '${_momentLabel(realization, before)} and '
        '${_momentLabel(realization, after)} '
        '${landmarkAt(after, realization).phrase}';
  }
  if (after != null && before == null) {
    return '${departure.noteLabel} before '
        '${_momentLabel(realization, after)} at the start';
  }
  if (before != null && after == null) {
    return '${departure.noteLabel} after '
        '${_momentLabel(realization, before)} at the end';
  }
  final position = before ?? after ?? departure.position.round();
  return '${departure.noteLabel} near '
      '${_momentLabel(realization, position)} '
      '${landmarkAt(position, realization).phrase}';
}

String _momentLabel(ExerciseRealization realization, int position) => {
  for (final note in realization.moments[position].notes)
    note.pitch.prettyLabel,
}.join(' + ');
