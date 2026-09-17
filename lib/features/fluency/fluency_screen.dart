import 'dart:math' as math;

import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import '../practice/exercise_presentation.dart';
import '../practice/practice_providers.dart';
import '../practice/task_help.dart';
import 'fluency_summary.dart';
import 'playing_pace_chart.dart';

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

enum _Lens { recall, tempo }

/// The key map: every scale around the circle of fifths, shaded by what has
/// been demonstrated.
class FluencyScreen extends ConsumerStatefulWidget {
  const FluencyScreen({super.key});

  @override
  ConsumerState<FluencyScreen> createState() => _FluencyScreenState();
}

class _FluencyScreenState extends ConsumerState<FluencyScreen> {
  _Lens _lens = _Lens.recall;
  HandConfiguration _hands = HandConfiguration.right;

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(fluencyReportProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluency'),
        actions: [
          IconButton(
            tooltip: 'Reading the key map',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showTermHelp(
              context,
              title: 'Reading the key map',
              entries: _helpEntries,
            ),
          ),
        ],
      ),
      body: switch (report) {
        AsyncError() => _Unavailable(
          onRetry: () => ref.invalidate(fluencyReportProvider),
        ),
        AsyncValue(hasValue: true, value: final report?) => _body(report),
        AsyncValue(hasValue: true) => const Center(
          child: Text('Fluency appears once you have started practicing.'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _body(FluencyReport report) {
    final summary = report.summary;
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final catalog = ref.watch(practiceCatalogProvider);
    final scales = catalog.whereType<ScaleMaterial>().toList();
    final sectors = keySectors(catalog);
    final shades = _Shades(theme.colorScheme);

    Color fill(ScaleMaterial material) {
      final fluency = summary[material];
      return switch (_lens) {
        _Lens.recall => shades.ofLevel(fluency.level),
        _Lens.tempo => shades.ofBand(
          TempoBand.of(fluency.unguidedTempo(_hands)),
        ),
      };
    }

    final headline = switch (_lens) {
      _Lens.recall =>
        '${summary.countAt(DemonstrationLevel.fromMemory, scales)} of '
            '${scales.length} scales played from memory',
      _Lens.tempo =>
        'Fastest tempo shown from memory, one octave, '
            '${_handsLabel(_hands).toLowerCase()}',
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

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: layout.gutter,
            vertical: 16,
          ),
          children: [
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
                  for (final hands in HandConfiguration.values)
                    ButtonSegment(
                      value: hands,
                      label: Text(_handsLabel(hands)),
                    ),
                ],
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
              onTap: (sector, form) => _openKey(summary, sectors[sector], form),
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
              'Major on the outside, then natural, harmonic, and melodic '
              'minor. Tap a key for its tempos.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            PlayingPaceChart(
              days: report.days,
              today: CalendarDay.localOf(DateTime.now()),
            ),
          ],
        ),
      ),
    );
  }

  String _keyDescription(FluencySummary summary, KeySector sector) => [
    for (final form in ScaleForm.values)
      if (sector.forms[form] case final material?)
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

  void _openKey(FluencySummary summary, KeySector sector, ScaleForm form) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) =>
            _KeySheet(summary: summary, sector: sector, initialForm: form),
      );
}

const List<(String, String)> _helpEntries = [
  (
    'Keys',
    'Each slice holds the scales that start on the same piano key, such as '
        'D♭ major and C♯ minor. Slices follow the circle of fifths, so '
        'neighbors share all but one note, but you can simply read the names.',
  ),
  (
    'Rings',
    'Major is the outer ring, then natural, harmonic, and melodic minor '
        'toward the middle.',
  ),
  ('From memory', 'You have played this scale without any notes shown.'),
  (
    'Notes previewed',
    'You have played it after seeing its notes, with them hidden while you '
        'played.',
  ),
  ('With cues', 'You have played it through while its notes were shown.'),
  (
    'Tempo',
    'The fastest tempo you played the scale at from memory, one octave, '
        'evenly enough to count. Other tempos are in each key.',
  ),
];

String _handsLabel(HandConfiguration hands) => switch (hands) {
  HandConfiguration.right => 'Right hand',
  HandConfiguration.left => 'Left hand',
  HandConfiguration.together => 'Together',
};

/// The ramp both lenses shade on, from nothing shown to the most shown.
class _Shades {
  final ColorScheme scheme;

  const _Shades(this.scheme);

  Color _step(int step) => switch (step) {
    0 => scheme.surfaceContainerHighest,
    _ => Color.lerp(scheme.surfaceContainerHighest, scheme.primary, step / 3)!,
  };

  Color ofLevel(DemonstrationLevel? level) =>
      _step(level == null ? 0 : level.index + 1);

  Color ofBand(TempoBand band) => _step(band.index);
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

/// The circle of keys, one ring per scale form.
class KeyWheel extends StatelessWidget {
  const KeyWheel({
    super.key,
    required this.sectors,
    required this.fill,
    required this.emptyColor,
    required this.labelStyle,
    required this.describe,
    required this.onTap,
  });

  final List<KeySector> sectors;
  final Color Function(ScaleMaterial material) fill;

  /// The color of a cell the catalog holds no scale for.
  final Color emptyColor;
  final TextStyle labelStyle;

  /// What a key reads as to assistive technology, which finds the wheel one
  /// key at a time.
  final String Function(KeySector sector) describe;
  final void Function(int sector, ScaleForm form) onTap;

  static const _geometry = KeyWheelGeometry();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final half = constraints.maxWidth / 2;
        return GestureDetector(
          onTapUp: (details) {
            final cell = _geometry.cellAt(
              (details.localPosition.dx - half) / half,
              (details.localPosition.dy - half) / half,
            );
            if (cell == null) return;
            if (!sectors[cell.sector].forms.containsKey(cell.form)) return;
            onTap(cell.sector, cell.form);
          },
          child: CustomPaint(
            size: Size.square(constraints.maxWidth),
            painter: _KeyWheelPainter(
              sectors: sectors,
              fill: fill,
              emptyColor: emptyColor,
              labelStyle: labelStyle,
              describe: describe,
              onTap: onTap,
            ),
          ),
        );
      },
    ),
  );
}

class _KeyWheelPainter extends CustomPainter {
  _KeyWheelPainter({
    required this.sectors,
    required this.fill,
    required this.emptyColor,
    required this.labelStyle,
    required this.describe,
    required this.onTap,
  });

  final List<KeySector> sectors;
  final Color Function(ScaleMaterial material) fill;
  final Color emptyColor;
  final TextStyle labelStyle;
  final String Function(KeySector sector) describe;
  final void Function(int sector, ScaleForm form) onTap;

  static const _geometry = KeyWheelGeometry();
  static const _sweep = 2 * math.pi / 12;

  /// The gap between neighboring cells, in logical pixels.
  static const _gap = 2.0;

  @override
  void paint(Canvas canvas, Size size) {
    final half = size.width / 2;
    final center = Offset(half, half);
    final separator = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _gap
      ..color = emptyColor;

    for (final (index, sector) in sectors.indexed) {
      // Canvas angles run clockwise from three o'clock.
      final start = _geometry.centerAngleOf(index) - _sweep / 2 - math.pi / 2;
      for (final form in ScaleForm.values) {
        final (outer, inner) = _geometry.ringOf(form);
        final path = _cell(center, outer * half, inner * half, start);
        final material = sector.forms[form];
        canvas
          ..drawPath(
            path,
            Paint()..color = material == null ? emptyColor : fill(material),
          )
          ..drawPath(path, separator);
      }
      _label(canvas, center, half, index, sector);
    }
  }

  Path _cell(Offset center, double outer, double inner, double start) => Path()
    ..arcTo(Rect.fromCircle(center: center, radius: outer), start, _sweep, true)
    ..arcTo(
      Rect.fromCircle(center: center, radius: inner),
      start + _sweep,
      -_sweep,
      false,
    )
    ..close();

  void _label(
    Canvas canvas,
    Offset center,
    double half,
    int index,
    KeySector sector,
  ) {
    final major = sector.majorTonic;
    if (major == null) return;
    final minor = sector.minorTonic;
    final painter = TextPainter(
      text: TextSpan(
        text: prettyTonic(major),
        style: labelStyle,
        children: [
          if (minor != null)
            TextSpan(
              text: '\n${prettyTonic(minor)}m',
              style: labelStyle.copyWith(
                fontSize: (labelStyle.fontSize ?? 14) * 0.75,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final angle = _geometry.centerAngleOf(index);
    final radius = (KeyWheelGeometry.outerRadius + 1) / 2 * half;
    final at = center + Offset(math.sin(angle), -math.cos(angle)) * radius;
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final half = size.width / 2;
    return [
      for (final (index, sector) in sectors.indexed)
        if (ScaleForm.values.where(sector.forms.containsKey).firstOrNull
            case final form?)
          CustomPainterSemantics(
            rect: _targetOf(index, half),
            properties: SemanticsProperties(
              label: describe(sector),
              button: true,
              textDirection: TextDirection.ltr,
              onTap: () => onTap(index, form),
            ),
          ),
    ];
  };

  Rect _targetOf(int sector, double half) {
    final target = _geometry.semanticTargetOf(sector);
    return Rect.fromCenter(
      center: Offset(half + target.x * half, half + target.y * half),
      width: target.side * half,
      height: target.side * half,
    );
  }

  @override
  bool shouldRepaint(_KeyWheelPainter old) => true;

  @override
  bool shouldRebuildSemantics(_KeyWheelPainter old) => true;
}

/// One key opened: each form's demonstration, and the focused form's tempos.
class _KeySheet extends StatefulWidget {
  const _KeySheet({
    required this.summary,
    required this.sector,
    required this.initialForm,
  });

  final FluencySummary summary;
  final KeySector sector;
  final ScaleForm initialForm;

  @override
  State<_KeySheet> createState() => _KeySheetState();
}

class _KeySheetState extends State<_KeySheet> {
  late ScaleForm _form = widget.initialForm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final now = DateTime.now();
    final forms = [
      for (final form in ScaleForm.values)
        if (widget.sector.forms[form] case final material?) (form, material),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (form, material) in forms) ...[
              _FormRow(
                fluency: widget.summary[material],
                now: now,
                selected: form == _form,
                onTap: () => setState(() => _form = form),
              ),
              if (form == _form) _TempoTable(fluency: widget.summary[material]),
            ],
            const SizedBox(height: 12),
            Text(
              'Beats per minute, the fastest you played evenly enough to '
              'count. A tempo shown with support names it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.fluency,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final MaterialFluency fluency;
  final DateTime now;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final demonstration = fluency.demonstration;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      selected: selected,
      title: Text(materialName(fluency.material)),
      subtitle: Text(
        demonstration == null
            ? 'Not demonstrated yet'
            : '${demonstrationName(demonstration.level)}, last '
                  '${demonstratedOn(demonstration.lastAt, now: now)}',
      ),
      trailing: Icon(selected ? Icons.expand_less : Icons.expand_more),
      onTap: onTap,
    );
  }
}

class _TempoTable extends StatelessWidget {
  const _TempoTable({required this.fluency});

  final MaterialFluency fluency;

  static const _octaves = [1, 2];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              const SizedBox.shrink(),
              for (final octaves in _octaves)
                _cell(
                  Text(
                    octaves == 1 ? '1 octave' : '$octaves octaves',
                    style: header,
                  ),
                ),
            ],
          ),
          for (final hands in HandConfiguration.values)
            TableRow(
              children: [
                _cell(Text(_handsLabel(hands), style: header)),
                for (final octaves in _octaves)
                  _cell(
                    Text(
                      switch (fluency.tempoFor(hands, octaves: octaves)) {
                        final tempo? => rungTempoName(tempo),
                        null => 'Not yet',
                      },
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(Widget child) =>
      Padding(padding: const EdgeInsets.fromLTRB(0, 6, 16, 6), child: child);
}
