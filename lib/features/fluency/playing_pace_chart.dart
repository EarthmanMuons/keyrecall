import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'fluency_summary.dart';
import 'fluency_trends.dart';

/// How fast each hand configuration has been playing, over recent weeks.
///
/// An observation of practice, not a capability claim, so it says playing pace
/// and nothing about progress. A week without playing breaks its line, and a
/// week of one or two attempts is drawn hollow.
class PlayingPaceChart extends StatelessWidget {
  const PlayingPaceChart({super.key, required this.days, required this.today});

  final List<FluencyDay> days;
  final CalendarDay today;

  static const int _weeks = 8;

  /// Which weeks carry a date on the axis: enough to place the rest.
  static const Set<int> _labeledWeeks = {0, 3, _weeks - 1};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _SeriesColors.of(theme.brightness);
    final series = {
      for (final hands in HandConfiguration.values)
        hands: recentWeeks(
          playingPace(days, hands: hands),
          today: today,
          count: _weeks,
        ),
    };
    final values = [
      for (final weeks in series.values)
        for (final week in weeks) ?week.medianTempoBpm,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Playing pace', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'How fast you played one octave in parallel motion during practice. '
          'Hollow points rest on one or two attempts.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (values.isEmpty)
          Text(
            'No measured one-octave, parallel-motion playing pace in the last '
            '$_weeks weeks.',
            style: theme.textTheme.bodyMedium,
          )
        else ...[
          Semantics(
            label: _description(series),
            excludeSemantics: true,
            child: SizedBox(
              height: 200,
              child: _chart(theme, colors, series, values),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final hands in HandConfiguration.values)
                _LegendLine(color: colors[hands], label: _handsName(hands)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chart(
    ThemeData theme,
    _SeriesColors colors,
    Map<HandConfiguration, List<WeeklyTempo>> series,
    List<double> values,
  ) {
    final bars = <(HandConfiguration, LineChartBarData)>[
      for (final MapEntry(key: hands, value: weeks) in series.entries)
        for (final run in contiguousRuns(weeks))
          (
            hands,
            LineChartBarData(
              spots: [
                for (final index in run)
                  FlSpot(index.toDouble(), weeks[index].medianTempoBpm!),
              ],
              color: colors[hands],
              barWidth: 2,
              dotData: FlDotData(
                getDotPainter: (spot, _, _, _) =>
                    isSparse(weeks[spot.x.toInt()])
                    ? FlDotCirclePainter(
                        radius: 3.5,
                        color: theme.colorScheme.surface,
                        strokeColor: colors[hands],
                        strokeWidth: 2,
                      )
                    : FlDotCirclePainter(
                        radius: 4,
                        color: colors[hands],
                        strokeColor: theme.colorScheme.surface,
                        strokeWidth: 2,
                      ),
              ),
            ),
          ),
    ];
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final interval = _gridInterval(high - low);
    final minY = ((low - interval / 2) / interval).floor() * interval;
    final maxY = ((high + interval / 2) / interval).ceil() * interval;
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final weeks = series.values.first;

    return LineChart(
      LineChartData(
        minX: -0.3,
        maxX: _weeks - 0.7,
        minY: minY,
        maxY: maxY,
        clipData: const FlClipData.none(),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: interval,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  value % interval == 0 ? value.round().toString() : '',
                  style: axisStyle,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                return SideTitleWidget(
                  meta: meta,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: Text(
                    value == index && _labeledWeeks.contains(index)
                        ? _weekLabel(weeks[index].week, index)
                        : '',
                    style: axisStyle,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            maxContentWidth: 180,
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  [
                    _handsName(bars[spot.barIndex].$1),
                    ...?playingPaceDetail(
                      series[bars[spot.barIndex].$1]![spot.x.toInt()],
                    ),
                  ].join('\n'),
                  theme.textTheme.bodySmall!.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                  ),
                  textAlign: TextAlign.start,
                ),
            ],
          ),
        ),
        lineBarsData: [for (final (_, bar) in bars) bar],
      ),
      duration: Duration.zero,
    );
  }

  String _weekLabel(CalendarDay week, int index) =>
      index == _weeks - 1 ? 'This week' : dayName(week, today: today);

  String _description(Map<HandConfiguration, List<WeeklyTempo>> series) => [
    'Playing pace over the last $_weeks weeks.',
    for (final MapEntry(key: hands, value: weeks) in series.entries)
      switch (weeks.lastWhere(
        (week) => week.medianTempoBpm != null,
        orElse: () => weeks.last,
      )) {
        final week when week.medianTempoBpm == null =>
          '${_handsName(hands)}: not measured.',
        final week =>
          '${_handsName(hands)}: ${playingPaceDetail(week)!.join(', ')}, '
              'week of ${dayName(week.week, today: today)}.',
      },
  ].join(' ');
}

/// Grid spacing in beats per minute: ten for a narrow range, twenty otherwise.
double _gridInterval(double span) => span <= 40 ? 10 : 20;

String _handsName(HandConfiguration hands) => switch (hands) {
  HandConfiguration.right => 'Right hand',
  HandConfiguration.left => 'Left hand',
  HandConfiguration.together => 'Together',
};

/// One color a hand configuration, the same in every chart, chosen to stay
/// apart under color-vision deficiency on either theme.
class _SeriesColors {
  final Map<HandConfiguration, Color> _colors;

  const _SeriesColors(this._colors);

  factory _SeriesColors.of(Brightness brightness) =>
      _SeriesColors(switch (brightness) {
        Brightness.light => const {
          HandConfiguration.right: Color(0xFFC06A00),
          HandConfiguration.left: Color(0xFF1F6FC2),
          HandConfiguration.together: Color(0xFFB0348C),
        },
        Brightness.dark => const {
          HandConfiguration.right: Color(0xFFD0801A),
          HandConfiguration.left: Color(0xFF4F95E6),
          HandConfiguration.together: Color(0xFFD060B0),
        },
      });

  Color operator [](HandConfiguration hands) => _colors[hands]!;
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 18,
        height: 3,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
