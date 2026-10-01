import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import '../practice/exercise_presentation.dart';
import 'fluency_summary.dart';

/// The materials of one key, each with its demonstration, and the expanded
/// one's tempos.
class DetailSheet extends StatefulWidget {
  const DetailSheet({super.key, required this.details, required this.initial});

  final List<MaterialDetail> details;
  final TechnicalMaterial? initial;

  @override
  State<DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<DetailSheet> {
  late TechnicalMaterial? _expanded = widget.initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final now = DateTime.now();

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final detail in widget.details) ...[
              _MaterialRow(
                fluency: detail.fluency,
                now: now,
                selected: detail.material == _expanded,
                onTap: () => setState(
                  () => _expanded = _expanded == detail.material
                      ? null
                      : detail.material,
                ),
              ),
              if (detail.material == _expanded)
                detail.hasTempo
                    ? _TempoTable(detail)
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'No tempo yet. One appears here once you play it '
                          'through at a steady pace, evenly enough to count.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
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

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
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
    return Semantics(
      expanded: selected,
      child: ListTile(
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
      ),
    );
  }
}

class _TempoTable extends StatelessWidget {
  const _TempoTable(this.detail);

  final MaterialDetail detail;

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
              for (final octaves in detail.octaveSpans)
                _cell(Text(octavesName(octaves), style: header)),
            ],
          ),
          for (final (:hands, :tempos) in detail.rows)
            TableRow(
              children: [
                _cell(Text(handsLabel(hands), style: header)),
                for (final tempo in tempos)
                  _cell(
                    Text(
                      tempo == null ? 'Not yet' : rungTempoName(tempo),
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
