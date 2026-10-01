import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'fluency_summary.dart';
import 'practice_activity.dart';
import 'report_groups.dart';
import 'weekly_chart_semantics.dart';

/// The days practiced, as a calendar of weeks shaded by attempts.
///
/// A record of practice, not of how it went, so it has its own ramp rather
/// than the report's recall shades. Inspecting a day, by touch, pointer, or
/// arrow keys, names it in a line beneath that stays put.
class ActivityCalendar extends StatefulWidget {
  const ActivityCalendar({
    super.key,
    required this.days,
    required this.groups,
    required this.today,
  });

  final List<FluencyDay> days;

  /// The report groups an inspected day's attempts are gathered into.
  final List<ReportGroup> groups;

  final CalendarDay today;

  @override
  State<ActivityCalendar> createState() => _ActivityCalendarState();
}

class _ActivityCalendarState extends State<ActivityCalendar> {
  late CalendarDay _inspected = widget.today;
  bool _scrubbing = false;

  static const double _gap = 2;
  static const double _monthRow = 16;

  static const _holdDelay = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shades = _ActivityShades(theme.colorScheme);
    final practiced = daysPracticed(widget.days, today: widget.today);
    final inspected = [
      for (final day in widget.days)
        if (day.day == _inspected) day,
    ].firstOrNull;
    final breakdown = inspected == null
        ? null
        : activityBreakdown(inspected.attemptsByFamily, widget.groups);

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
            final count = weeksThatFit(width);
            final weeks = activityWeeks(
              widget.days,
              today: widget.today,
              count: count,
            );
            final pitch = width / count;
            final column = weeks.indexWhere(
              (week) => week.week == _inspected.weekStart,
            );
            void inspect(Offset position) => _inspectAt(position, weeks, pitch);
            return Focus(
              onKeyEvent: (node, event) => _onKey(event, weeks.first.week),
              child: RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: {
                  TapGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        TapGestureRecognizer
                      >(
                        TapGestureRecognizer.new,
                        (recognizer) =>
                            recognizer.onTapDown = (details) =>
                                inspect(details.localPosition),
                      ),
                  HorizontalDragGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        HorizontalDragGestureRecognizer
                      >(HorizontalDragGestureRecognizer.new, (recognizer) {
                        recognizer.onStart = (details) =>
                            _scrub(details.localPosition, inspect);
                        recognizer.onUpdate = (details) =>
                            _scrub(details.localPosition, inspect);
                        recognizer.onEnd = (_) => _endScrub();
                        recognizer.onCancel = _endScrub;
                      }),
                  // Holding first frees the finger to move in any direction,
                  // across weekdays as well as weeks.
                  LongPressGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer
                      >(
                        () => LongPressGestureRecognizer(duration: _holdDelay),
                        (recognizer) {
                          recognizer.onLongPressStart = (details) =>
                              _scrub(details.localPosition, inspect);
                          recognizer.onLongPressMoveUpdate = (details) =>
                              _scrub(details.localPosition, inspect);
                          recognizer.onLongPressEnd = (_) => _endScrub();
                          recognizer.onLongPressCancel = _endScrub;
                        },
                      ),
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    WeeklyChartSemantics(
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
                    // Above the calendar, where the finger scrubbing it
                    // cannot cover the day it names.
                    if (_scrubbing && column >= 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: _monthRow + pitch * 7 + 4,
                        child: IgnorePointer(
                          child: Align(
                            alignment: Alignment(
                              (column + 0.5) / count * 2 - 1,
                              0,
                            ),
                            child: Material(
                              color: theme.colorScheme.inverseSurface,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                  dayName(_inspected, today: widget.today),
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.onInverseSurface,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activityDayDescription(
                      _inspected,
                      inspected?.attempts ?? 0,
                      today: widget.today,
                    ),
                    style: theme.textTheme.bodyMedium,
                  ),
                  // Always present, so the calendar never shifts as days
                  // with and without a breakdown are inspected.
                  Text(
                    breakdown ?? '',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
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

  void _scrub(Offset position, void Function(Offset position) inspect) {
    if (!_scrubbing) setState(() => _scrubbing = true);
    inspect(position);
  }

  void _endScrub() => setState(() => _scrubbing = false);

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

/// A teal ramp of its own, opposite the theme's orange, so activity stays
/// vivid in both themes and never reads as a recall level.
class _ActivityShades {
  final ColorScheme scheme;

  const _ActivityShades(this.scheme);

  static const _light = [
    Color(0xFFB2EBE0),
    Color(0xFF5FCFBC),
    Color(0xFF1FA693),
    Color(0xFF0B6E62),
  ];

  /// Brightest at the top, as dark surfaces read more activity as more light.
  static const _dark = [
    Color(0xFF0E4A43),
    Color(0xFF12786B),
    Color(0xFF23A996),
    Color(0xFF6EE2CF),
  ];

  Color of(ActivityBand band) => switch (band) {
    ActivityBand.none => scheme.surfaceContainerHighest,
    _ =>
      (scheme.brightness == Brightness.dark ? _dark : _light)[band.index - 1],
  };
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
