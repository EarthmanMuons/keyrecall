import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../practice/practice_providers.dart';
import 'fluency_summary.dart';
import 'report_groups.dart';

/// What the report reads: the summary the key map shares with its sheet, and
/// the days the charts are drawn from.
typedef FluencyReport = ({FluencySummary summary, List<FluencyDay> days});

/// What the selected profile has demonstrated and played, read fresh each time
/// the report opens.
///
/// Null when nobody on this install has been placed yet.
final fluencyReportProvider = FutureProvider.autoDispose<FluencyReport?>((
  ref,
) async {
  final lifecycle = await ref.watch(profileLifecycleProvider.future);
  final profile = await lifecycle.repository.selectedOrOldest();
  if (profile == null) return null;
  final store = lifecycle.store;
  final lifetime = await store.lifetimeOf(profile.id);
  final history = await readFluencyHistory(
    store.boundTo(lifetime),
    profile.id,
    partition: DayPartition.local(),
    onSaveFailure: (error, _) =>
        debugPrint('[fluency] history computed but not saved: $error'),
  );
  return (
    summary: FluencySummary.of(
      history.days,
      catalog: ref.watch(practiceCatalogProvider),
    ),
    days: history.days,
  );
});

/// The catalog organized into the report's groups.
final fluencyGroupsProvider = Provider<List<ResolvedGroup>>(
  (ref) => resolveReportGroups(ref.watch(practiceCatalogProvider)),
);

/// The report once it has been read, or why it cannot be shown yet.
class FluencyReportView extends ConsumerWidget {
  const FluencyReportView({super.key, required this.builder});

  final Widget Function(FluencyReport report) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (ref.watch(fluencyReportProvider)) {
        AsyncError() => _Unavailable(
          onRetry: () => ref.invalidate(fluencyReportProvider),
        ),
        AsyncValue(hasValue: true, value: final report?) => builder(report),
        AsyncValue(hasValue: true) => const Center(
          child: Text('Fluency appears once you have started practicing.'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
}

/// The padding a fluency screen's scrolling content takes, clear of the
/// system's bottom inset with room past the last section.
EdgeInsets fluencyListPadding(BuildContext context, double gutter) =>
    EdgeInsets.fromLTRB(
      gutter,
      16,
      gutter,
      32 + MediaQuery.paddingOf(context).bottom,
    );

/// How many of [materials] have been played from memory, as a sentence.
String fromMemoryHeadline(
  FluencySummary summary,
  List<TechnicalMaterial> materials,
  ReportGroup group,
) =>
    '${summary.countAt(DemonstrationLevel.fromMemory, materials)} of '
    '${materials.length} ${group.plural} played from memory';

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Your practice history could not be read.'),
        const SizedBox(height: 12),
        FilledButton.tonal(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
