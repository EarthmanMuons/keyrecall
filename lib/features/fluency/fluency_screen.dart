import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'activity_calendar.dart';
import 'fluency_report.dart';
import 'fluency_shades.dart';
import 'fluency_summary.dart';
import 'group_report_screen.dart';
import 'key_wheel.dart';
import 'report_groups.dart';

/// The fluency overview: practice activity, then a card per report group,
/// each previewing its view where it has a wheel, and opening its report.
class FluencyScreen extends ConsumerWidget {
  const FluencyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = Layout.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Fluency')),
      body: FluencyReportView(
        builder: (report) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: layout.gutter,
                vertical: 16,
              ),
              children: [
                ActivityCalendar(
                  days: report.days,
                  today: CalendarDay.localOf(DateTime.now()),
                ),
                const SizedBox(height: 24),
                for (final resolved in ref.watch(fluencyGroupsProvider))
                  _GroupCard(resolved: resolved, summary: report.summary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.resolved, required this.summary});

  final ResolvedGroup resolved;
  final FluencySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surfaceContainerLow;
    final shades = FluencyShades(theme.colorScheme);
    final group = resolved.group;
    return Card(
      color: background,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => GroupReportScreen(group: group),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (group.view case WheelView(:final rings)) ...[
                KeyWheelPreview(
                  sectors: keySectors(resolved.materials, rings),
                  fill: (material) => shades.ofLevel(summary[material].level),
                  emptyColor: background,
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      fromMemoryHeadline(summary, resolved.materials, group),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
