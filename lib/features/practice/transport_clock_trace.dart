import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:path_provider/path_provider.dart';

/// The scripted takes, in the order they are meant to be played.
///
/// Deliberately boring. Each one is a question about the transport rather than
/// about playing, and the point of scripting them is that the shape of the
/// performance is known in advance: a discontinuity in the clocks can then be
/// attributed to delivery rather than to somebody hesitating.
enum TransportTake {
  pulse(
    'Steady pulse',
    'A scale or a repeated note against a metronome at a known tempo. '
        'The baseline: what both clocks do while nothing is going wrong.',
  ),
  chords(
    'Block chords',
    'Three or four notes struck together, several times. Whether the notes '
        'of one chord share a transport stamp says whether a stamp is packet '
        'time or message time.',
  ),
  pause(
    'Long pause',
    'Play, stop for ten seconds or so, then play again. What the clocks do '
        'across a gap nobody is filling.',
  ),
  stall(
    'Loaded stall',
    'Keep playing while the app is made busy: scroll hard, open and close '
        'screens. Separates delivery delay from playing.',
  ),
  background(
    'Background and resume',
    'Play, background the app for half a minute, return, play again. The '
        'boundary records the gap even though nothing arrives during it.',
  ),
  reconnect(
    'Disconnect and reconnect',
    'Play, power the instrument off or walk out of range, bring it back, '
        'play again. Whether a transport clock survives its own link.',
  );

  const TransportTake(this.label, this.protocol);

  /// What to call it in the trace.
  final String label;

  /// What to do at the instrument.
  final String protocol;

  /// The identifier written into the file.
  String get id => name;
}

/// One recording of the raw transport boundary.
///
/// Records are appended exactly as the boundary handed them over, including
/// the ones it went on to reject. Nothing is summarized: the first traces
/// exist to decide what is worth computing, and a recorder that had already
/// decided would answer its own question.
@immutable
class TransportClockTrace {
  /// Which scripted take is being recorded.
  final TransportTake take;

  /// Anything worth saying that the protocol does not, such as the tempo.
  final String note;

  /// Whether the boundary is being watched right now.
  final bool isRecording;

  /// What has been recorded, in arrival order.
  final List<MidiTransportRecord> records;

  /// Where the last trace was written.
  final String? savedTo;

  const TransportClockTrace({
    this.take = TransportTake.pulse,
    this.note = '',
    this.isRecording = false,
    this.records = const [],
    this.savedTo,
  });

  /// How many messages the transport delivered.
  int get deliveries => records.whereType<MidiTransportDelivery>().length;

  /// How many boundaries fell inside the take.
  int get boundaries => records.whereType<MidiTransportBoundary>().length;

  TransportClockTrace copyWith({
    TransportTake? take,
    String? note,
    bool? isRecording,
    List<MidiTransportRecord>? records,
    String? savedTo,
  }) => TransportClockTrace(
    take: take ?? this.take,
    note: note ?? this.note,
    isRecording: isRecording ?? this.isRecording,
    records: records ?? this.records,
    savedTo: savedTo ?? this.savedTo,
  );
}

/// What the trace was recorded on, which is half of what makes it comparable.
///
/// One BLE keyboard on one phone answers nothing on its own. The header is
/// what lets an iPhone trace be read beside an Android one, or BLE beside USB,
/// without having to remember which file came from where.
Map<String, Object?> traceHeaderJson({
  required TransportTake take,
  required String note,
  required MidiDevice? instrument,
}) => {
  'recorded_at': DateTime.now().toUtc().toIso8601String(),
  'take': take.id,
  'note': note,
  'platform': {
    'os': Platform.operatingSystem,
    'os_version': Platform.operatingSystemVersion,
    'debug': kDebugMode,
  },
  'instrument': instrument == null
      ? null
      : {
          'id': instrument.id,
          'name': instrument.name,
          'transport': instrument.transport.name,
        },
};

/// One record, written flat so a column of it can be read without walking a
/// tree.
Map<String, Object?> recordToJson(MidiTransportRecord record) =>
    switch (record) {
      MidiTransportDelivery(:final envelope, :final live) => {
        'seq': record.sequence,
        'kind': 'delivery',
        'arrival_ms': record.arrivalTimestampMs,
        'transport_ts': envelope.transportTimestamp,
        'device': envelope.source.deviceId,
        'transport': envelope.source.transport,
        'session': envelope.source.sessionId,
        'channel': envelope.channel,
        'message': envelope.message.kind.name,
        'note': envelope.message.note,
        'velocity': envelope.message.velocity,
        'sustain': envelope.message.sustainValue,
        'live': live,
      },
      MidiTransportBoundary(
        :final kind,
        :final session,
        :final adopted,
        :final fault,
        :final detail,
      ) =>
        {
          'seq': record.sequence,
          'kind': 'boundary',
          'arrival_ms': record.arrivalTimestampMs,
          'boundary': kind.name,
          'session': session,
          'adopted_device': adopted?.deviceId,
          'adopted_session': adopted?.sessionId,
          'fault': fault?.name,
          'detail': detail,
        },
    };

/// The trace, held above the screen so leaving it does not discard a take.
final transportClockTraceProvider =
    NotifierProvider<TransportClockTraceNotifier, TransportClockTrace>(
      TransportClockTraceNotifier.new,
    );

class TransportClockTraceNotifier extends Notifier<TransportClockTrace> {
  StreamSubscription<MidiTransportRecord>? _watching;
  List<MidiTransportRecord> _records = [];

  @override
  TransportClockTrace build() {
    ref.onDispose(() => unawaited(_watching?.cancel()));
    return const TransportClockTrace();
  }

  /// Chooses which scripted take is being played.
  void use(TransportTake take) => state = state.copyWith(take: take);

  /// Notes the tempo, the room, or whatever else the protocol does not say.
  void annotate(String note) => state = state.copyWith(note: note);

  /// Starts watching the raw boundary.
  ///
  /// Watching is all it does. The boundary hands over what it was already
  /// handling, so a take cannot change what the app admitted or played.
  void start() {
    if (state.isRecording) return;
    _records = [];
    _watching = ref
        .read(midiInputProvider.notifier)
        .transportRecords
        .listen(_append);
    state = state.copyWith(isRecording: true, records: const []);
  }

  /// Stops watching, keeping what was recorded.
  void stop() {
    unawaited(_watching?.cancel());
    _watching = null;
    state = state.copyWith(isRecording: false, records: _records);
  }

  /// Throws the take away.
  void discard() {
    stop();
    _records = [];
    state = state.copyWith(records: const []);
  }

  void _append(MidiTransportRecord record) {
    _records = [..._records, record];
    // Published rather than counted in place, so the screen can show a take
    // filling up and somebody can tell a silent instrument from a stalled one.
    state = state.copyWith(records: _records);
  }

  /// Writes the take where the Files app and Finder can reach it.
  ///
  /// Documents rather than Application Support, for the reason the calibration
  /// takes are there: characterization is meant to leave the phone, and
  /// practice history is not.
  Future<String> save() async {
    final directory = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/transport-clocks',
    )..createSync(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final path = '${directory.path}/$stamp-${state.take.id}.json';

    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        ...traceHeaderJson(
          take: state.take,
          note: state.note,
          instrument: ref.read(midiDeviceManagerProvider).connectedDevice,
        ),
        'records': [for (final record in state.records) recordToJson(record)],
      }),
    );
    state = state.copyWith(savedTo: path);
    return path;
  }
}

/// Records what the transports actually do, so the clock mapper can be
/// designed against behavior rather than against assumptions.
///
/// It watches the raw boundary and writes down what crossed it. It converts
/// nothing, corrects nothing, and computes nothing: the first traces exist to
/// decide what is worth computing, and a tool that had already decided would
/// bake its assumptions into the dataset meant to test them.
///
/// See `analysis/transport-clocks/` for the protocol and `docs/roadmap.md` for
/// what this feeds.
class TransportClockScreen extends ConsumerStatefulWidget {
  const TransportClockScreen({super.key});

  @override
  ConsumerState<TransportClockScreen> createState() =>
      _TransportClockScreenState();
}

class _TransportClockScreenState extends ConsumerState<TransportClockScreen> {
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    ref.read(transportClockTraceProvider.notifier).annotate(_note.text);
    final path = await ref.read(transportClockTraceProvider.notifier).save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('saved ${Uri.file(path).pathSegments.last}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trace = ref.watch(transportClockTraceProvider);
    final recorder = ref.read(transportClockTraceProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transport clocks'),
        actions: [
          IconButton(
            tooltip: 'Save this take on the phone',
            onPressed: trace.records.isEmpty ? null : _save,
            icon: const Icon(Icons.save_alt),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Both clocks, exactly as they arrive, with what the boundary '
            'rejected left in. Nothing here is converted or corrected.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          // One line rather than six tiles of protocol. The protocol belongs
          // under the take that was chosen, where it is about to be followed,
          // and not above the button that starts it: a picker tall enough to
          // hold all six pushed every control off the bottom of the screen.
          //
          // A null callback is what locks it while a take is running. Which
          // take this is belongs to the file, and changing it halfway would
          // mislabel what was recorded.
          DropdownButton<TransportTake>(
            value: trace.take,
            isExpanded: true,
            onChanged: trace.isRecording
                ? null
                : (chosen) => recorder.use(chosen!),
            items: [
              for (final take in TransportTake.values)
                DropdownMenuItem(value: take, child: Text(take.label)),
            ],
          ),
          const SizedBox(height: 8),
          Text(trace.take.protocol, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            enabled: !trace.isRecording,
            decoration: const InputDecoration(
              labelText: 'Anything the protocol does not say',
              hintText: '80bpm, right hand, two octaves',
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: trace.isRecording ? recorder.stop : recorder.start,
                child: Text(trace.isRecording ? 'Stop' : 'Start take'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: trace.records.isEmpty ? null : recorder.discard,
                child: const Text('Discard'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${trace.isRecording ? 'recording' : 'stopped'} \u00b7 '
            '${trace.deliveries} delivered, ${trace.boundaries} boundaries',
            style: theme.textTheme.bodyMedium,
          ),
          if (trace.savedTo != null) ...[
            const SizedBox(height: 4),
            Text(
              'last saved ${Uri.file(trace.savedTo!).pathSegments.last}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          // The tail rather than the take: enough to see that an instrument is
          // reaching the app and that stamps are moving, which is all anybody
          // can read off a phone mid-take. The file is the artifact.
          for (final record in trace.records.reversed.take(_visibleRecords))
            Text(
              _describe(record),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
        ],
      ),
    );
  }

  static const int _visibleRecords = 20;

  static String _describe(MidiTransportRecord record) => switch (record) {
    MidiTransportDelivery(:final envelope, :final live) =>
      '${record.sequence}  ${record.arrivalTimestampMs}ms  '
          'ts=${envelope.transportTimestamp}  '
          '${envelope.message.kind.name} ${envelope.message.note ?? ''}'
          '${live ? '' : '  STALE'}',
    MidiTransportBoundary(:final kind, :final fault) =>
      '${record.sequence}  ${record.arrivalTimestampMs}ms  '
          '-- ${kind.name}${fault == null ? '' : ' ${fault.name}'} --',
  };
}
