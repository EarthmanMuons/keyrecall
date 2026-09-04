import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:material_ui/material_ui.dart';

import '../input/input.dart';
import 'attempt_preview.dart';
import 'loop_failure.dart';
import 'onset_diagnostic.dart';
import 'practice_providers.dart';
import 'timing_calibration.dart';
import 'trajectory_export.dart';

/// What the practice loop is doing, for whoever is developing it.
///
/// Not a design and not a learner-facing screen. It makes the state machine
/// visible: which profile is running, what the model expected of the exercise
/// on screen, what live input is arriving, and what the last attempt committed.
/// The instruments below it record the takes that timing constants are set
/// from.
class DeveloperScreen extends ConsumerWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(practiceLoopProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Developer')),
      body: switch (loop) {
        AsyncError(:final error, :final stackTrace) => LoopFailure(
          error: error,
          stackTrace: stackTrace,
          showsStackTrace: true,
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
  Widget build(BuildContext context, WidgetRef ref) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      _Section(
        title: 'Profile',
        children: [
          _Field('name', loop.profile.displayName),
          _Field('id', loop.profile.id),
          _Field('attempts recorded', '${loop.attemptsRecorded}'),
          _Field('session', loop.session.sessionId),
          // A decision an earlier run persisted and never closed. The practice
          // screen presents it like any other, under this same id, so it is
          // reported here rather than being something to resolve.
          if (loop.pending case final pending?) ...[
            _Field('resumed attempt', pending.attemptId),
            _Field('decided at', '${pending.decidedAt.toLocal()}'),
          ],
        ],
      ),
      if (loop.note != null)
        _Section(title: 'Note', children: [Text(loop.note!)]),
      if (loop.presented != null) _PredictionPanel(loop.presented!.prediction),
      const _InputPanel(),
      if (loop.lastCommitted != null) _CommittedPanel(loop.lastCommitted!),
      const _Tools(),
    ],
  );
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

class _CommittedPanel extends StatelessWidget {
  const _CommittedPanel(this.record);

  final AttemptRecord record;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'Last committed',
    children: [
      _Field('sequence', '#${record.journalSequence}'),
      _Field('attempt', record.identity.attemptId),
      _Field('material', record.exercise.material.materialId),
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
        OutlinedButton(
          onPressed: () => MidiDeviceSheet.show(context),
          child: const Text('Choose instrument'),
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

/// The instruments that produce data about the app rather than about a
/// learner.
class _Tools extends ConsumerWidget {
  const _Tools();

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Section(
    title: 'Tools',
    children: [
      _Tool(
        icon: Icons.style,
        title: 'Presentation cases',
        subtitle: 'One exercise at every rung, without a loop behind it',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const AttemptPreviewScreen(),
          ),
        ),
      ),
      _Tool(
        icon: Icons.timeline,
        title: 'Onset spacing',
        subtitle: 'How far apart notes arrive, for the grouping window',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const OnsetDiagnosticScreen(),
          ),
        ),
      ),
      _Tool(
        icon: Icons.straighten,
        title: 'Timing calibration',
        subtitle: 'The takes behind the timing constants',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const TimingCalibrationScreen(),
          ),
        ),
      ),
      _Tool(
        icon: Icons.list_alt,
        title: 'Export trajectory',
        subtitle: 'Write this profile’s history where Files can reach it',
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            final path = await exportTrajectory(ref);
            messenger.showSnackBar(
              SnackBar(content: Text('saved ${path.split('/').last}')),
            );
          } on Object catch (error) {
            messenger.showSnackBar(SnackBar(content: Text('$error')));
          }
        },
      ),
      _Tool(
        icon: Icons.science_outlined,
        title: 'Enable experimental arpeggios',
        subtitle:
            'Offers the arpeggio catalog to this run only. Its generation '
            'policy and family transfer are unvalidated fixtures.',
        trailing: Switch(
          value: ref.watch(experimentalArpeggiosProvider),
          onChanged: ref.read(experimentalArpeggiosProvider.notifier).use,
        ),
        onTap: () => ref
            .read(experimentalArpeggiosProvider.notifier)
            .use(!ref.read(experimentalArpeggiosProvider)),
      ),
      _Tool(
        icon: Icons.restart_alt,
        title: 'Reopen the sitting',
        subtitle: 'Read it back from storage, as a relaunch would',
        onTap: () => ref.read(practiceLoopProvider.notifier).reopen(),
      ),
    ],
  );
}

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// What the tool shows about its own state, for the ones that hold any.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: trailing,
    onTap: onTap,
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
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
