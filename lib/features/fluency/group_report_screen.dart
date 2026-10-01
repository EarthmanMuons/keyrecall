import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import '../practice/exercise_presentation.dart';
import '../practice/hands_icon.dart';
import '../practice/task_help.dart';
import 'detail_sheet.dart';
import 'fluency_report.dart';
import 'fluency_shades.dart';
import 'fluency_summary.dart';
import 'key_wheel.dart';
import 'playing_pace_chart.dart';
import 'recall_milestones_chart.dart';
import 'report_groups.dart';

enum _Lens { recall, tempo }

/// One report group: its primary view, then how it has developed.
class GroupReportScreen extends ConsumerStatefulWidget {
  const GroupReportScreen({super.key, required this.group});

  final ReportGroup group;

  @override
  ConsumerState<GroupReportScreen> createState() => _GroupReportScreenState();
}

class _GroupReportScreenState extends ConsumerState<GroupReportScreen> {
  _Lens _lens = _Lens.recall;
  HandConfiguration _hands = HandConfiguration.right;

  ReportGroup get _group => widget.group;

  @override
  Widget build(BuildContext context) {
    final title = switch (_group.view) {
      WheelView() => 'Reading the key map',
      MaterialListView() => 'Reading the list',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_group.name),
        actions: [
          IconButton(
            tooltip: title,
            icon: const Icon(Icons.help_outline),
            onPressed: () =>
                showTermHelp(context, title: title, entries: _helpEntries()),
          ),
        ],
      ),
      body: FluencyReportView(builder: _body),
    );
  }

  Widget _body(FluencyReport report) {
    final layout = Layout.of(context);
    final materials = [
      for (final resolved in ref.watch(fluencyGroupsProvider))
        if (resolved.group.id == _group.id) ...resolved.materials,
    ];
    final today = CalendarDay.localOf(DateTime.now());

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: layout.gutter,
            vertical: 16,
          ),
          children: [
            ...switch (_group.view) {
              final WheelView view => _wheel(report.summary, view, materials),
              MaterialListView() => _list(report.summary, materials),
            },
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            RecallMilestonesChart(
              days: report.days,
              materialIds: {
                for (final material in materials) material.materialId,
              },
              singular: _group.singular,
              plural: _group.plural,
              today: today,
            ),
            if (_group.paceCohort case final cohort?) ...[
              const SizedBox(height: 32),
              PlayingPaceChart(
                days: report.days,
                cohort: cohort(materials),
                today: today,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _wheel(
    FluencySummary summary,
    WheelView view,
    List<TechnicalMaterial> materials,
  ) {
    final theme = Theme.of(context);
    final sectors = keySectors(materials, view.rings);
    final shades = FluencyShades(theme.colorScheme);

    Color fill(TechnicalMaterial material) {
      final fluency = summary[material];
      return switch (_lens) {
        _Lens.recall => shades.ofLevel(fluency.level),
        _Lens.tempo => shades.ofBand(
          TempoBand.of(fluency.unguidedTempo(_hands)),
        ),
      };
    }

    final headline = switch (_lens) {
      _Lens.recall => fromMemoryHeadline(summary, materials, _group),
      _Lens.tempo =>
        'Fastest tempo shown from memory, one octave, '
            '${handsLabel(_hands).toLowerCase()}',
    };
    final legend = switch (_lens) {
      _Lens.recall => [
        for (final level in [null, ...DemonstrationLevel.values])
          (shades.ofLevel(level), demonstrationName(level)),
      ],
      _Lens.tempo => [
        (shades.ofBand(TempoBand.none), 'None yet'),
        (shades.ofBand(TempoBand.under72), 'Under 72'),
        (shades.ofBand(TempoBand.from72), '72 to 99'),
        (shades.ofBand(TempoBand.from100), '100 and up'),
      ],
    };

    return [
      SegmentedButton<_Lens>(
        segments: const [
          ButtonSegment(value: _Lens.recall, label: Text('Recall')),
          ButtonSegment(value: _Lens.tempo, label: Text('Tempo')),
        ],
        selected: {_lens},
        onSelectionChanged: (selected) =>
            setState(() => _lens = selected.single),
      ),
      if (_lens == _Lens.tempo) ...[
        const SizedBox(height: 8),
        SegmentedButton<HandConfiguration>(
          segments: [
            for (final hands in const [
              HandConfiguration.left,
              HandConfiguration.right,
              HandConfiguration.together,
            ])
              ButtonSegment(
                value: hands,
                icon: HandsIcon(hands),
                tooltip: handsLabel(hands),
              ),
          ],
          showSelectedIcon: false,
          selected: {_hands},
          onSelectionChanged: (selected) =>
              setState(() => _hands = selected.single),
        ),
      ],
      const SizedBox(height: 16),
      KeyWheel(
        sectors: sectors,
        fill: fill,
        emptyColor: theme.colorScheme.surface,
        labelStyle: theme.textTheme.labelLarge!.copyWith(
          color: theme.colorScheme.onSurface,
        ),
        describe: (sector) => _keyDescription(summary, sector),
        onTap: (sector, ring) => _openDetails(
          summary,
          sectors[sector].materials,
          sectors[sector].cells[ring],
        ),
      ),
      const SizedBox(height: 12),
      Text(
        headline,
        style: theme.textTheme.bodyLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          for (final (color, label) in legend)
            _LegendEntry(color: color, label: label),
        ],
      ),
      const SizedBox(height: 12),
      Text(
        view.caption,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    ];
  }

  List<Widget> _list(
    FluencySummary summary,
    List<TechnicalMaterial> materials,
  ) => [
    Text(
      fromMemoryHeadline(summary, materials, _group),
      style: Theme.of(context).textTheme.bodyLarge,
    ),
    const SizedBox(height: 8),
    for (final material in materials)
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(materialName(material)),
        subtitle: Text(demonstrationName(summary[material].level)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openDetails(summary, [material], material),
      ),
  ];

  String _keyDescription(FluencySummary summary, KeySector sector) => [
    for (final material in sector.materials)
      _cellDescription(summary[material]),
  ].join('; ');

  String _cellDescription(MaterialFluency fluency) {
    final name = materialName(fluency.material);
    return switch (_lens) {
      _Lens.recall =>
        '$name, ${demonstrationName(fluency.level).toLowerCase()}',
      _Lens.tempo => switch (fluency.unguidedTempo(_hands)) {
        final tempo? => '$name, ${tempo.round()} from memory',
        null => '$name, no tempo from memory yet',
      },
    };
  }

  void _openDetails(
    FluencySummary summary,
    List<TechnicalMaterial> materials,
    TechnicalMaterial? initial,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => DetailSheet(
      details: [
        for (final material in materials) MaterialDetail.of(summary[material]),
      ],
      initial: initial,
    ),
  );

  List<(String, String)> _helpEntries() => [
    if (_group.view case WheelView(:final ringsHelp)) ...[
      (
        'Keys',
        'Each slice holds the ${_group.plural} that start on the same piano '
            'key, such as D♭ major and C♯ minor. Slices follow the circle of '
            'fifths, so neighbors share all but one note, but you can simply '
            'read the names.',
      ),
      ('Rings', ringsHelp),
    ],
    ('From memory', 'You have played it without any notes shown.'),
    (
      'Notes previewed',
      'You have played it after seeing its notes, with them hidden while you '
          'played.',
    ),
    ('With cues', 'You have played it through while its notes were shown.'),
    if (_group.view is WheelView)
      (
        'Tempo',
        'The fastest tempo you played it at from memory, one octave, evenly '
            'enough to count. Other tempos are in each key.',
      ),
  ];
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.label});

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
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
