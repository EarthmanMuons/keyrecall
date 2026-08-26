import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../demo_input/demo_input.dart';
import '../input/input.dart';
import 'attempt_preview.dart';
import 'attempt_screen.dart';
import 'onset_diagnostic.dart';
import 'practice_providers.dart';
import 'reported_result.dart';

/// The app's entry screen: a way into [AttemptScreen], and outside release
/// builds a development panel for driving the practice loop by hand.
///
/// The panel is deliberately not a design. It exists to make the state machine
/// visible and operable end to end: the scheduler picks a real exercise, live
/// input crosses the real source boundary, and a hand-reported result goes
/// through the real update, journal, and replay path. Learner-facing attempts
/// no longer report themselves; they are measured. The buttons here remain as
/// a way to drive the loop without an instrument.
///
/// Nothing in the panel should be carried into the learner-facing UI.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(practiceLoopProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KeyRecall dev panel'),
        actions: [
          // Debug and profile, not release: a profile build is how this gets
          // taken to a real instrument across the room.
          if (!kReleaseMode)
            IconButton(
              tooltip: 'Look at fixed presentation cases',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const AttemptPreviewScreen(),
                ),
              ),
              icon: const Icon(Icons.style),
            ),
          IconButton(
            tooltip: 'Open the practice screen',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const AttemptScreen(),
              ),
            ),
            icon: const Icon(Icons.piano),
          ),
          if (!kReleaseMode)
            IconButton(
              tooltip: 'Measure how far apart notes arrive',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const OnsetDiagnosticScreen(),
                ),
              ),
              icon: const Icon(Icons.timeline),
            ),
          IconButton(
            tooltip: 'Reopen from storage, as a relaunch would',
            onPressed: () => ref.read(practiceLoopProvider.notifier).reopen(),
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: switch (loop) {
        AsyncError(:final error, :final stackTrace) => _Failure(
          error: error,
          stackTrace: stackTrace,
        ),
        AsyncData(:final value) => _Loop(value),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Loop extends ConsumerWidget {
  const _Loop(this.loop);

  final PracticeLoopState loop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(practiceLoopProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Profile',
          children: [
            _Field('name', loop.profile.displayName),
            _Field('id', loop.profile.id),
            _Field('attempts recorded', '${loop.attemptsRecorded}'),
            _Field('session', loop.session.sessionId),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _confirmErase(context, notifier),
              child: const Text('Start over, erasing history'),
            ),
          ],
        ),
        if (loop.pending != null)
          _PendingBanner(
            pending: loop.pending!,
            onAbandon: notifier.abandonPending,
          ),
        if (loop.note != null && loop.pending == null)
          _Section(title: 'Note', children: [Text(loop.note!)]),
        if (loop.exercise != null) ...[
          _ExercisePanel(loop.exercise!),
          if (loop.presented != null)
            _PredictionPanel(loop.presented!.prediction),
          _ReportPanel(onReport: notifier.report),
        ] else
          _Section(
            title: 'Nothing presented',
            children: [
              const Text(
                'The scheduler admitted nothing for this slot. That consumed '
                'a slot, so ask for another one rather than retrying this.',
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: notifier.reopen,
                child: const Text('Open another sitting'),
              ),
            ],
          ),
        const _InputPanel(),
        if (loop.lastCommitted != null) _CommittedPanel(loop.lastCommitted!),
      ],
    );
  }
}

/// Asks before destroying recorded practice.
Future<void> _confirmErase(
  BuildContext context,
  PracticeLoopNotifier notifier,
) async {
  final erase = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Start over?'),
      content: const Text(
        'Every recorded attempt for this profile is deleted, and the learner '
        'model goes back to placement. There is no undo.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Erase'),
        ),
      ],
    ),
  );
  if (erase ?? false) await notifier.eraseHistory();
}

class _ExercisePanel extends StatelessWidget {
  const _ExercisePanel(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final conditions = exercise.conditions;
    return _Section(
      title: 'Play this',
      children: [
        Text(
          '${exercise.material.tonic} ${exercise.material.form.id}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        _Field('hands', conditions.hands.id),
        _Field('octaves', '${conditions.octaves}'),
        _Field('direction', conditions.direction.id),
        _Field('tempo', '${conditions.tempoBpm.round()} bpm'),
        _Field('pattern', exercise.pattern.id),
        _Field('guidance', _guidance(exercise.guidance)),
      ],
    );
  }

  static String _guidance(GuidanceContext guidance) {
    final rung = switch (guidance.independence) {
      2 => 'unguided',
      1 => 'notes previewed, then hidden',
      _ => 'cues visible throughout',
    };
    return guidance.isRetrievalObserved
        ? '$rung (retrieval tested)'
        : '$rung (retrieval not tested)';
  }
}

class _PredictionPanel extends StatelessWidget {
  const _PredictionPanel(this.prediction);

  final Prediction prediction;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'What the model expected',
    children: [
      _Field('independent retrieval', _p(prediction.independentRetrievalP)),
      _Field('material available', _p(prediction.materialAvailableP)),
      _Field('execution', _p(prediction.executionP)),
      _Field('topology', _p(prediction.topologyP)),
    ],
  );

  static String _p(double value) => '${(value * 100).toStringAsFixed(1)}%';
}

class _ReportPanel extends StatelessWidget {
  const _ReportPanel({required this.onReport});

  final Future<void> Function(ReportedResult) onReport;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'What happened',
    children: [
      const Text(
        'Standing in for measurement. Everything downstream of this is real.',
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final result in ReportedResult.values)
            Tooltip(
              message: result.description,
              child: FilledButton.tonal(
                onPressed: () => onReport(result),
                child: Text(result.label),
              ),
            ),
        ],
      ),
    ],
  );
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.pending, required this.onAbandon});

  final PendingDecision pending;
  final Future<void> Function() onAbandon;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Unanswered attempt',
    tone: Theme.of(context).colorScheme.errorContainer,
    children: [
      const Text(
        'An earlier run showed this exercise and never recorded what '
        'happened. Nothing invents an outcome, because nothing observed one: '
        'answer it below, or abandon it and record nothing.',
      ),
      const SizedBox(height: 8),
      _Field('attempt', pending.attemptId),
      _Field('decided at', '${pending.decidedAt.toLocal()}'),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: onAbandon,
        child: const Text('Abandon, recording nothing'),
      ),
    ],
  );
}

class _CommittedPanel extends StatelessWidget {
  const _CommittedPanel(this.record);

  final AttemptRecord record;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Last committed',
    children: [
      _Field('sequence', '#${record.journalSequence}'),
      _Field('attempt', record.identity.attemptId),
      _Field(
        'material',
        '${record.exercise.material.tonic} '
            '${record.exercise.material.form.id}',
      ),
      _Field('termination', record.closure.termination.id),
      ...switch (record.closure.measurement) {
        Measured(:final outcome) => [
          _Field('retrieval', outcome.retrieval.name),
          _Field('motor', outcome.motorScore.toStringAsFixed(3)),
        ],
        MeasurementUnavailable(:final reason) => [
          _Field('measurement', 'unavailable: ${reason.id}'),
        ],
      },
    ],
  );
}

/// Which instrument is connected, if any.
class _InstrumentField extends ConsumerWidget {
  const _InstrumentField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(midiConnectionStateProvider);
    return _Field(
      'instrument',
      connection.isConnected
          ? (connection.deviceDisplayName ?? 'connected')
          : 'not connected',
    );
  }
}

/// Live input, straight from the normalized stream.
class _InputPanel extends ConsumerWidget {
  const _InputPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(inputActivityProvider);
    final source = ref.watch(inputSourceProvider);
    final demo = ref.read(demoInputProvider.notifier);

    return _Section(
      title: 'Input',
      children: [
        _Field('source', source.name),
        // Only when MIDI is the chosen source: reading the connection state
        // starts the Bluetooth stack, which a panel showing a label has no
        // business doing.
        if (source == InputSourceKind.midi) const _InstrumentField(),
        _Field('events seen', '${activity.eventCount}'),
        _Field('resets', '${activity.resetCount}'),
        _Field('pedal', activity.isPedalDown ? 'down' : 'up'),
        _Field('held', _notes(activity.pressedNoteNumbers)),
        _Field('ringing under pedal', _notes(activity.sustainedNoteNumbers)),
        _Field('sounding', _notes(activity.soundingNoteNumbers)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              // Fixed notes, unrelated to the exercise above. The synthetic
              // instrument does not know what was asked for, and nothing here
              // judges what it played.
              onPressed: () =>
                  demo.playSequence(const [60, 62, 64, 65, 67, 69, 71, 72]),
              child: const Text('Play something'),
            ),
            FilledButton.tonal(
              onPressed: () =>
                  demo.setPedalDown(!ref.read(demoInputProvider).isPedalDown),
              child: const Text('Toggle pedal'),
            ),
            FilledButton.tonal(
              onPressed: demo.releaseAll,
              child: const Text('Lift hands'),
            ),
            OutlinedButton(
              onPressed: () => ref.read(inputSourceProvider.notifier).toggle(),
              child: Text(
                source == InputSourceKind.demo ? 'Use MIDI' : 'Use synthetic',
              ),
            ),
            OutlinedButton(
              onPressed: () async {
                final device = await MidiDeviceSheet.show(context);
                // Connecting is the explicit decision the source provider
                // wants: a device appearing is not one, but choosing it is.
                if (device != null) {
                  ref
                      .read(inputSourceProvider.notifier)
                      .use(InputSourceKind.midi);
                }
              },
              child: const Text('Choose instrument'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (activity.isIdle)
          const Text('nothing yet')
        else
          for (final line in activity.recent)
            Text(line, style: const TextStyle(fontFamily: 'monospace')),
      ],
    );
  }

  static String _notes(Set<int> notes) =>
      notes.isEmpty ? 'nothing' : (notes.toList()..sort()).join(' ');
}

class _Failure extends ConsumerWidget {
  const _Failure({required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text('$error', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () => ref.invalidate(practiceLoopProvider),
        child: const Text('Try again'),
      ),
      const SizedBox(height: 12),
      Text('$stackTrace', style: const TextStyle(fontFamily: 'monospace')),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.tone});

  final String title;
  final List<Widget> children;
  final Color? tone;

  @override
  Widget build(BuildContext context) => Card(
    color: tone,
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 170, child: Text(label)),
        Expanded(
          child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
        ),
      ],
    ),
  );
}
