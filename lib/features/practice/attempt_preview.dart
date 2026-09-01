import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'attempt_screen.dart';
import 'exercise_presentation.dart';
import 'presentation_policy.dart';

/// Fixed exercises for looking at the practice screen, reachable in any build
/// but a release one.
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
                '${handsName(sample.conditions.hands)}, '
                '${octavesName(sample.conditions.octaves)}, '
                '${sample.conditions.tempoBpm.round()} bpm\n'
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

class _Preview extends StatefulWidget {
  const _Preview(this.exercise);

  final Exercise exercise;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  /// Which modality this case is being looked at in. Practice policy picks
  /// one; here both are reachable, so the same exercise can be compared as
  /// marked keys and as notation.
  CueModality _modality = CueModality.keyboard;

  /// Which tempo support this case is being heard under.
  ///
  /// Reachable here and nowhere else. Practice policy is count-in only, and a
  /// metronome the learner could switch on mid-sitting would change what an
  /// attempt observes without the record saying so: presentation is derivable
  /// from the exercise today, and staying derivable is why it is not stored.
  /// These cases record nothing, so hearing one costs nothing.
  TempoSupport _tempoSupport = TempoSupport.countInOnly;

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final policy = presentationFor(exercise.guidance);
    final presentation = PresentationConditions(
      pitchCue: policy.pitchCue,
      cueModality: policy.pitchCue.suppliesMaterial ? _modality : null,
      motorCue: policy.motorCue,
      performanceFeedback: policy.performanceFeedback,
      tempoSupport: _tempoSupport,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(guidanceName(exercise.guidance)),
        actions: [
          IconButton(
            tooltip: _tempoSupport == TempoSupport.metronomeThroughout
                ? 'Count in and stop'
                : 'Keep the click going',
            onPressed: () => setState(() {
              _tempoSupport = _tempoSupport == TempoSupport.metronomeThroughout
                  ? TempoSupport.countInOnly
                  : TempoSupport.metronomeThroughout;
            }),
            icon: Icon(
              _tempoSupport == TempoSupport.metronomeThroughout
                  ? Icons.timer
                  : Icons.timer_off,
            ),
          ),
          if (policy.pitchCue.suppliesMaterial)
            IconButton(
              tooltip: 'Show the cue the other way',
              onPressed: () => setState(() {
                _modality = _modality == CueModality.keyboard
                    ? CueModality.staff
                    : CueModality.keyboard;
              }),
              icon: Icon(
                _modality == CueModality.keyboard
                    ? Icons.music_note
                    : Icons.piano,
              ),
            ),
        ],
      ),
      body: AttemptView(
        exercise: exercise,
        presentation: presentation,
        // Fabricated cases record nothing, so finishing one just leaves.
        onFinish: (_) async {
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
