import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import '../input/input.dart';

/// One note-on, as raw as it arrives.
///
/// Not a [PerformanceTranscript] note: this is for calibrating what "at the
/// same time" means, so it carries no spelling and no key context. The only
/// interesting fields are which key and when.
class Onset {
  /// Which key.
  final int noteNumber;

  /// When it arrived, on the input stream's clock.
  final int timestampMs;

  const Onset({required this.noteNumber, required this.timestampMs});
}

/// A take: what has been recorded, and whether it is still running.
@immutable
class OnsetTake {
  /// The note-ons collected so far, in arrival order.
  final List<Onset> onsets;

  /// Whether notes are still being collected.
  final bool isRecording;

  const OnsetTake({this.onsets = const [], this.isRecording = false});
}

/// Raw note-ons, recorded while a take is running.
final onsetRecorderProvider =
    NotifierProvider<OnsetRecorderNotifier, OnsetTake>(
      OnsetRecorderNotifier.new,
    );

class OnsetRecorderNotifier extends Notifier<OnsetTake> {
  @override
  OnsetTake build() {
    ref.listen<AsyncValue<InputTemporalEvent>>(inputTemporalEventsProvider, (
      _,
      next,
    ) {
      final event = next.value;
      if (state.isRecording && event is InputTemporalNoteOnEvent) {
        state = OnsetTake(
          isRecording: true,
          onsets: [
            ...state.onsets,
            Onset(noteNumber: event.noteNumber, timestampMs: event.timestampMs),
          ],
        );
      }
    }, fireImmediately: true);
    return const OnsetTake();
  }

  /// Starts a fresh take.
  void start() => state = const OnsetTake(isRecording: true);

  /// Stops, keeping what was recorded.
  void stop() => state = OnsetTake(onsets: state.onsets);
}

/// How far apart the notes of a hands-together attempt actually arrive.
///
/// The grouping window in the alignment contract is empirical, and this is
/// what it is meant to be calibrated from: play a hands-together scale on a
/// real instrument and read the gaps. Nothing here groups anything or decides
/// a threshold; it reports what the instrument sent.
///
/// See `docs/domain-model/alignment-contract.md`.
class OnsetDiagnosticScreen extends ConsumerStatefulWidget {
  const OnsetDiagnosticScreen({super.key});

  @override
  ConsumerState<OnsetDiagnosticScreen> createState() =>
      _OnsetDiagnosticScreenState();
}

class _OnsetDiagnosticScreenState extends ConsumerState<OnsetDiagnosticScreen> {
  /// What this take was meant to be: comfortable, deliberately tight,
  /// staggered, rolled, and at what tempo and direction.
  ///
  /// Kept beside the notes rather than in them. What the instrument sent is
  /// evidence; what it was meant to be is the label a person puts on it, and
  /// the two must not be confused when the gaps are read back.
  final TextEditingController _label = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  /// Writes the take to a file the Files app and Finder can reach.
  ///
  /// Documents rather than Application Support, which is where practice
  /// history lives: takes are meant to leave the phone, and journals are not.
  Future<void> _save(List<Onset> onsets) async {
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/onsets',
    )..createSync(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final slug = _label.text.isEmpty
        ? 'take'
        : _label.text.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
    final file = File('${directory.path}/$stamp-$slug.json');
    file.writeAsStringSync(_json(onsets, _label.text));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('saved ${file.uri.pathSegments.last}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final take = ref.watch(onsetRecorderProvider);
    final onsets = take.onsets;
    final recorder = ref.read(onsetRecorderProvider.notifier);
    final deltas = _deltasOf(onsets);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Onsets'),
        actions: [
          IconButton(
            tooltip: 'Copy this take as JSON',
            onPressed: onsets.isEmpty
                ? null
                : () => Clipboard.setData(
                    ClipboardData(text: _json(onsets, _label.text)),
                  ),
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: 'Save this take on the phone',
            onPressed: onsets.isEmpty ? null : () => _save(onsets),
            icon: const Icon(Icons.save_alt),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Play with both hands. Each row is a note-on and how long after '
            'the one before it arrived.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'What this take is',
              hintText: 'comfortable, 80bpm, up and down',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: take.isRecording ? recorder.stop : recorder.start,
                child: Text(take.isRecording ? 'Stop' : 'Start take'),
              ),
              const SizedBox(width: 12),
              Text('${onsets.length} notes'),
            ],
          ),
          const SizedBox(height: 16),
          if (deltas.isNotEmpty) _Summary(deltas: deltas),
          const SizedBox(height: 8),
          for (final (index, onset) in onsets.indexed)
            Text(
              index == 0
                  ? 'note ${onset.noteNumber}'
                  : 'note ${onset.noteNumber}   '
                        '+${onset.timestampMs - onsets[index - 1].timestampMs}ms',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
        ],
      ),
    );
  }

  List<int> _deltasOf(List<Onset> onsets) => [
    for (var index = 1; index < onsets.length; index++)
      onsets[index].timestampMs - onsets[index - 1].timestampMs,
  ];

  String _json(List<Onset> onsets, String label) =>
      '{"label":${jsonEncode(label)},"notes":['
      '${[for (final onset in onsets) '{"note":${onset.noteNumber},'
            '"ms":${onset.timestampMs}}'].join(',')}]}';
}

/// The gaps, sorted, so a cluster of near-simultaneous pairs is visible
/// without plotting anything.
class _Summary extends StatelessWidget {
  const _Summary({required this.deltas});

  final List<int> deltas;

  @override
  Widget build(BuildContext context) {
    final sorted = [...deltas]..sort();
    final smallest = sorted.take(10).join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('gaps, smallest first: $smallest'),
        Text('median: ${sorted[sorted.length ~/ 2]}ms'),
        Text('largest: ${sorted.last}ms'),
      ],
    );
  }
}
