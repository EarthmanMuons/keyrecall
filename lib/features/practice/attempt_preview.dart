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

/// The cases worth looking at: a staff that wraps, a short one spread to the
/// width, a left-hand one in a flat key, and the densest grand staff.
final List<Exercise> _samples = [
  Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: 2,
  ),
  Exercise.linear(
    material: ArpeggioMaterial('E', ArpeggioQuality.minor),
    hands: HandConfiguration.right,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
  ),
  Exercise.linear(
    material: TechnicalMaterial('Eb', ScaleForm.melodicMinor),
    hands: HandConfiguration.left,
    tempoBpm: 100,
  ),
  Exercise.linear(
    material: TechnicalMaterial('F#', ScaleForm.harmonicMinor),
    hands: HandConfiguration.together,
    octaves: 2,
    tempoBpm: 60,
  ),
];

class _Preview extends StatefulWidget {
  const _Preview(this.exercise);

  final Exercise exercise;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  /// Which modality this case is being looked at in, when not the one
  /// practice policy picks, so the same exercise can be compared as marked
  /// keys and as notation.
  CueModality? _modality;

  /// Which tempo support this case is being heard under.
  ///
  /// Reachable here and nowhere else. Practice policy is count-in only, and a
  /// metronome the learner could switch on mid-session would change what an
  /// attempt observes; only policy decides that for an attempt anything is
  /// recorded of. These cases record nothing, so hearing one costs nothing.
  TempoSupport _tempoSupport = TempoSupport.countInOnly;

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final policy = presentationFor(exercise.guidance);
    final modality = policy.pitchCue.suppliesMaterial
        ? _modality ?? policy.cueModality
        : null;
    final presentation = PresentationConditions(
      pitchCue: policy.pitchCue,
      cueModality: modality,
      motorCue: policy.motorCue,
      performanceFeedback: policy.performanceFeedback,
      tempoSupport: _tempoSupport,
      // The locator travels over a cue staff, so looking at the same case as
      // marked keys has nothing for it to travel over.
      locatorFeedback: cueOnStaff(modality)
          ? policy.locatorFeedback
          : LocatorFeedback.none,
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
          if (modality != null)
            PopupMenuButton<CueModality>(
              tooltip: 'Where the cue is shown',
              initialValue: modality,
              onSelected: (choice) => setState(() => _modality = choice),
              icon: Icon(switch (modality) {
                CueModality.keyboard => Icons.piano,
                CueModality.staff => Icons.music_note,
                CueModality.keyboardAndStaff => Icons.queue_music,
              }),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: CueModality.keyboardAndStaff,
                  child: Text('Keyboard and staff'),
                ),
                PopupMenuItem(
                  value: CueModality.keyboard,
                  child: Text('Keyboard'),
                ),
                PopupMenuItem(value: CueModality.staff, child: Text('Staff')),
              ],
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
