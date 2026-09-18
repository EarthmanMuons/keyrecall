import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'fluency_shades.dart';
import 'fluency_summary.dart';
import 'fluency_trends.dart';
import 'weekly_chart_semantics.dart';

/// How many scales have reached each level of recall, week by week.
///
/// Milestones rather than current recall: each scale counts at the strongest
/// level it has ever been demonstrated at, so the bars only grow, and the title
/// says so rather than letting a learner expect forgetting to show here.
class RecallMilestonesChart extends StatelessWidget {
  const RecallMilestonesChart({
    super.key,
    required this.days,
    required this.materialIds,
    required this.today,
  });

  final List<FluencyDay> days;
  final Set<String> materialIds;
  final CalendarDay today;

  static const int _weeks = 8;

  /// Strongest at the base, so from memory is the bar's foundation.
  static const _stackOrder = [
    DemonstrationLevel.fromMemory,
    DemonstrationLevel.notesPreviewed,
    DemonstrationLevel.cued,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = FluencyShades(theme.colorScheme);
    final weeks = recallMilestones(
      days,
      materialIds: materialIds,
      today: today,
      count: _weeks,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recall milestones', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Scales by the most independent way you have played them. A scale '
          'keeps its milestone, so the bars only grow.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        if (weeks.last.total == 0)
          Text('No scales demonstrated yet.', style: theme.textTheme.bodyMedium)
        else ...[
          WeeklyChartSemantics(
            labels: [for (final week in weeks) _description(week)],
            child: SizedBox(height: 180, child: _chart(theme, shades, weeks)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final level in _stackOrder)
                _LegendSwatch(
                  color: shades.ofLevel(level),
                  label: demonstrationName(level),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _chart(
    ThemeData theme,
    FluencyShades shades,
    List<WeeklyMilestones> weeks,
  ) {
    final highest = weeks.map((week) => week.total).reduce(math.max);
    final interval = math.max(1, (highest / 4).ceil()).toDouble();
    final maxY = (highest / interval).ceil() * interval;
    final axisStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return BarChart(
      BarChartData(
        maxY: maxY,
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
              getTitlesWidget: (value, meta) {
                final index = value.round();
                return SideTitleWidget(
                  meta: meta,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                  child: Text(
                    {0, 3, _weeks - 1}.contains(index)
                        ? _weekLabel(weeks[index].week, index)
                        : '',
                    style: axisStyle,
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItem: (group, _, _, _) => BarTooltipItem(
              [
                'Week of ${dayName(weeks[group.x].week, today: today)}',
                for (final level in _stackOrder)
                  '${weeks[group.x].countAt(level)} '
                      '${demonstrationName(level).toLowerCase()}',
              ].join('\n'),
              theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onInverseSurface,
              ),
              textAlign: TextAlign.start,
            ),
          ),
        ),
        barGroups: [
          for (final (index, week) in weeks.indexed)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: week.total.toDouble(),
                  width: 18,
                  color: Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                  rodStackItems: _stack(theme, shades, week),
                ),
              ],
            ),
        ],
      ),
      duration: Duration.zero,
    );
  }

  List<BarChartRodStackItem> _stack(
    ThemeData theme,
    FluencyShades shades,
    WeeklyMilestones week,
  ) {
    final items = <BarChartRodStackItem>[];
    var from = 0.0;
    for (final level in _stackOrder) {
      final count = week.countAt(level);
      if (count == 0) continue;
      items.add(
        BarChartRodStackItem(
          from,
          from + count,
          shades.ofLevel(level),
          borderSide: BorderSide(color: theme.colorScheme.surface),
        ),
      );
      from += count;
    }
    return items;
  }

  String _weekLabel(CalendarDay week, int index) =>
      index == _weeks - 1 ? 'This week' : dayName(week, today: today);

  String _description(WeeklyMilestones week) => [
    'Week of ${dayName(week.week, today: today)}.',
    for (final level in _stackOrder)
      '${week.countAt(level)} ${demonstrationName(level).toLowerCase()}.',
  ].join(' ');
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
