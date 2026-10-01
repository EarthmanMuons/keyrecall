import 'package:flutter/services.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'fluency_summary.dart';
import 'practice_activity.dart';
import 'weekly_chart_semantics.dart';

/// The days practiced, as a calendar of weeks shaded by attempts.
///
/// A record of practice, not of how it went, so it has its own ramp rather
/// than the report's recall shades. Inspecting a day, by touch, pointer, or
/// arrow keys, names it in a line beneath that stays put.
class ActivityCalendar extends StatefulWidget {
  const ActivityCalendar({super.key, required this.days, required this.today});

  final List<FluencyDay> days;
  final CalendarDay today;

  @override
  State<ActivityCalendar> createState() => _ActivityCalendarState();
}

class _ActivityCalendarState extends State<ActivityCalendar> {
  late CalendarDay _inspected = widget.today;

  static const double _gap = 2;
  static const double _monthRow = 16;

  /// The narrowest cell a whole year may be drawn with before the calendar
  /// shows half of one instead.
  static const double _narrowestYearCell = 10;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = _ActivityShades(theme.colorScheme);
    final practiced = daysPracticed(widget.days, today: widget.today);
    final attemptsOn = {for (final day in widget.days) day.day: day.attempts};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Practice activity', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          '$practiced ${practiced == 1 ? 'day' : 'days'} practiced in the '
          'past 30',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final count = width / 52 - _gap >= _narrowestYearCell ? 52 : 26;
            final weeks = activityWeeks(
              widget.days,
              today: widget.today,
              count: count,
            );
            final pitch = width / count;
            return Focus(
              onKeyEvent: (node, event) => _onKey(event, weeks.first.week),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) =>
                    _inspectAt(details.localPosition, weeks, pitch),
                onHorizontalDragUpdate: (details) =>
                    _inspectAt(details.localPosition, weeks, pitch),
                child: WeeklyChartSemantics(
                  labels: [
                    for (final week in weeks)
                      activityWeekDescription(week, today: widget.today),
                  ],
                  child: CustomPaint(
                    size: Size(width, _monthRow + pitch * 7),
                    painter: _CalendarPainter(
                      weeks: weeks,
                      pitch: pitch,
                      shades: shades,
                      inspected: _inspected,
                      highlight: theme.colorScheme.onSurface,
                      labelStyle: theme.textTheme.labelSmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                activityDayDescription(
                  _inspected,
                  attemptsOn[_inspected] ?? 0,
                  today: widget.today,
                ),
                style: theme.textTheme.bodyMedium,
              ),
            ),
            ExcludeSemantics(
              child: Row(
                children: [
                  Text('Less', style: theme.textTheme.bodySmall),
                  for (final band in ActivityBand.values)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(left: 3),
                      decoration: BoxDecoration(
                        color: shades.of(band),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  const SizedBox(width: 3),
                  Text('More', style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _inspectAt(Offset position, List<ActivityWeek> weeks, double pitch) {
    final column = (position.dx / pitch).floor().clamp(0, weeks.length - 1);
    final row = ((position.dy - _monthRow) / pitch).floor().clamp(0, 6);
    final week = weeks[column];
    if (week.attempts[row] == null) return;
    setState(() => _inspected = week.dayAt(row));
  }

  KeyEventResult _onKey(KeyEvent event, CalendarDay first) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final step = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -7,
      LogicalKeyboardKey.arrowRight => 7,
      LogicalKeyboardKey.arrowUp => -1,
      LogicalKeyboardKey.arrowDown => 1,
      _ => null,
    };
    if (step == null) return KeyEventResult.ignored;
    final next = _inspected.plusDays(step);
    if (next.compareTo(first) >= 0 && next.compareTo(widget.today) <= 0) {
      setState(() => _inspected = next);
    }
    return KeyEventResult.handled;
  }
}

class _ActivityShades {
  final ColorScheme scheme;

  const _ActivityShades(this.scheme);

  Color of(ActivityBand band) => Color.lerp(
    scheme.surfaceContainerHighest,
    scheme.tertiary,
    band.index / (ActivityBand.values.length - 1),
  )!;
}

class _CalendarPainter extends CustomPainter {
  _CalendarPainter({
    required this.weeks,
    required this.pitch,
    required this.shades,
    required this.inspected,
    required this.highlight,
    required this.labelStyle,
  });

  final List<ActivityWeek> weeks;
  final double pitch;
  final _ActivityShades shades;
  final CalendarDay inspected;
  final Color highlight;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const top = _ActivityCalendarState._monthRow;
    const gap = _ActivityCalendarState._gap;
    var labelEnd = double.negativeInfinity;
    for (final (column, week) in weeks.indexed) {
      final left = column * pitch;
      for (final (row, attempts) in week.attempts.indexed) {
        if (attempts == null) continue;
        final cell = RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top + row * pitch, pitch - gap, pitch - gap),
          const Radius.circular(2),
        );
        canvas.drawRRect(
          cell,
          Paint()..color = shades.of(ActivityBand.of(attempts)),
        );
        if (week.dayAt(row) == inspected) {
          canvas.drawRRect(
            cell.inflate(1),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = highlight,
          );
        }
      }
      if (_monthStartingIn(week) case final month? when left >= labelEnd) {
        final label = TextPainter(
          text: TextSpan(text: monthName(month), style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(left, 0));
        labelEnd = left + label.width + 4;
      }
    }
  }

  /// The month whose first day falls in [week], if one does.
  int? _monthStartingIn(ActivityWeek week) {
    for (var weekday = 0; weekday < 7; weekday++) {
      final day = week.dayAt(weekday);
      if (day.day == 1) return day.month;
    }
    return null;
  }

  @override
  bool shouldRepaint(_CalendarPainter old) => true;
}
