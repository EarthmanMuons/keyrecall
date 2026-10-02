import 'package:material_ui/material_ui.dart';

/// The separator between items sharing a line.
const String itemSeparator = ' · ';

/// [items] gathered into lines no wider than [maxWidth], in order, never
/// breaking an item and never leaving a separator at either end of a line.
///
/// An item wider than [maxWidth] on its own still gets a line to itself.
List<String> packItems(
  List<String> items,
  double maxWidth,
  double Function(String text) measure,
) {
  final lines = <String>[];
  for (final item in items) {
    final joined = lines.isEmpty ? null : '${lines.last}$itemSeparator$item';
    if (joined != null && measure(joined) <= maxWidth) {
      lines.last = joined;
    } else {
      lines.add(item);
    }
  }
  return lines;
}

/// A centered run of items such as a task's conditions, wrapping between
/// items rather than inside them.
class ItemLines extends StatelessWidget {
  const ItemLines(this.items, {this.style, super.key});

  final List<String> items;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(this.style);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);

    double measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) => Text(
        packItems(items, constraints.maxWidth, measure).join('\n'),
        style: style,
        textAlign: TextAlign.center,
      ),
    );
  }
}
