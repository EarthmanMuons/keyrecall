import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'fluency_report.dart';
import 'group_report_screen.dart';
import 'report_groups.dart';

/// The fluency overview: a card per report group, each opening its report.
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
                for (final resolved in ref.watch(fluencyGroupsProvider))
                  _GroupCard(
                    group: resolved.group,
                    headline: fromMemoryHeadline(
                      report.summary,
                      resolved.materials,
                      resolved.group,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.headline});

  final ReportGroup group;
  final String headline;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(group.name),
      subtitle: Text(headline),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => GroupReportScreen(group: group),
        ),
      ),
    ),
  );
}
