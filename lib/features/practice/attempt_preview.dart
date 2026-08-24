import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'attempt_screen.dart';
import 'exercise_presentation.dart';
import 'reported_result.dart';

/// Fixed exercises for looking at the practice screen, reachable in debug
/// builds only.
///
/// The scheduler decides what to present, so a particular rung and key cannot
/// be asked for through the loop. These cases skip it entirely: they are
/// fabricated, no decision exists behind them, and reporting one records
/// nothing. Nothing here may write to the journal, since an outcome with no
/// decision is exactly the false history the transaction path prevents.
class AttemptPreviewScreen extends StatelessWidget {
  const AttemptPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Presentation cases')),
    body: ListView(
      children: [
        for (final sample in _samples)
          for (final guidance in GuidanceContext.ladder)
            ListTile(
              title: Text(materialName(sample.material)),
              subtitle: Text(
                '${conditionsLine(sample.conditions)}\n'
                '${guidanceName(guidance)}',
              ),
              isThreeLine: true,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => _Preview(sample.withGuidance(guidance)),
                ),
              ),
            ),
      ],
    ),
  );
}

/// The cases worth looking at: a plain one, the densest one, and a left-hand
/// one in a flat key.
final List<Exercise> _samples = [
  Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
  ),
  Exercise.linear(
    material: TechnicalMaterial('F#', ScaleForm.harmonicMinor),
    hands: HandConfiguration.together,
    tempoBpm: 60,
  ),
  Exercise.linear(
    material: TechnicalMaterial('Eb', ScaleForm.melodicMinor),
    hands: HandConfiguration.left,
    octaves: 1,
    tempoBpm: 100,
  ),
];

class _Preview extends StatelessWidget {
  const _Preview(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(guidanceName(exercise.guidance))),
    body: AttemptView(
      exercise: exercise,
      onReport: (ReportedResult _) async {
        if (!context.mounted) return;
        Navigator.of(context).pop();
      },
    ),
  );
}
