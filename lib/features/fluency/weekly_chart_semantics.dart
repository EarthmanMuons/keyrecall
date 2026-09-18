import 'package:flutter/semantics.dart';

import 'package:material_ui/material_ui.dart';

/// One accessible entry per week, including weeks without a measurement.
class WeeklyChartSemantics extends StatelessWidget {
  const WeeklyChartSemantics({
    super.key,
    required this.labels,
    required this.child,
  });

  final List<String> labels;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      ExcludeSemantics(child: child),
      Positioned.fill(
        child: IgnorePointer(
          child: Row(
            children: [
              for (final (index, label) in labels.indexed)
                Expanded(
                  child: Semantics(
                    container: true,
                    sortKey: OrdinalSortKey(index.toDouble()),
                    label: label,
                    child: const SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
