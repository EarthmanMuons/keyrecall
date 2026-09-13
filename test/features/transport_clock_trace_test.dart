import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

import 'package:keyrecall/features/practice/transport_clock_trace.dart';

void main() {
  const source = InputSourceIdentity(
    deviceId: 'jamcorder',
    transport: 'ble',
    sessionId: 'midi-2',
  );

  test('a delivery keeps both clocks apart and uninterpreted', () {
    final json = recordToJson(
      MidiTransportDelivery(
        sequence: 7,
        arrivalTimestampMs: 8123,
        live: true,
        envelope: const RawInputEnvelope(
          source: source,
          channel: 3,
          transportTimestamp: 2416352,
          arrivalTimestampMs: 8123,
          message: RawInputMessage(
            kind: RawInputKind.noteOn,
            note: 64,
            velocity: 91,
          ),
        ),
      ),
    );

    expect(json['seq'], 7);
    expect(json['kind'], 'delivery');
    expect(json['arrival_ms'], 8123);
    expect(
      json['transport_ts'],
      2416352,
      reason: 'the transport stamp is written as it arrived, in its own domain',
    );
    expect(json['session'], 'midi-2');
    expect(json['channel'], 3);
    expect(json['message'], 'noteOn');
    expect(json['note'], 64);
    expect(json['velocity'], 91);
    expect(json['live'], isTrue);
  });

  test('a rejected delivery is written down like any other', () {
    final json = recordToJson(
      MidiTransportDelivery(
        sequence: 0,
        arrivalTimestampMs: 10,
        live: false,
        envelope: const RawInputEnvelope(
          source: source,
          arrivalTimestampMs: 10,
          message: RawInputMessage(
            kind: RawInputKind.noteOn,
            note: 200,
            velocity: 91,
          ),
        ),
      ),
    );

    expect(
      json['note'],
      200,
      reason: 'a trace of the transport is not a trace of what survived it',
    );
    expect(json['live'], isFalse);
    expect(json['transport_ts'], isNull);
  });

  test('a boundary says what closed the observation and what was adopted', () {
    final json = recordToJson(
      const MidiTransportBoundary(
        sequence: 12,
        arrivalTimestampMs: 8130,
        kind: MidiTransportBoundaryKind.observationFailed,
        adopted: source,
        fault: InputIntegrityFault.observationGap,
        detail: 'observation suspended',
      ),
    );

    expect(json['kind'], 'boundary');
    expect(json['boundary'], 'observationFailed');
    expect(json['fault'], 'observationGap');
    expect(json['adopted_session'], 'midi-2');
    expect(json['detail'], 'observation suspended');
  });

  test('the header names what the trace can be compared against', () {
    final header = traceHeaderJson(
      take: TransportTake.chords,
      note: '80bpm, right hand',
      instrument: const MidiDevice(
        id: 'jamcorder',
        name: 'JamCorder',
        transport: MidiTransportType.ble,
        isConnected: true,
      ),
    );

    expect(header['take'], 'chords');
    expect(header['note'], '80bpm, right hand');
    expect((header['instrument']! as Map)['transport'], 'ble');
    expect((header['platform']! as Map)['os'], isNotEmpty);
  });

  test('a trace with no instrument is still a trace', () {
    final header = traceHeaderJson(
      take: TransportTake.pulse,
      note: '',
      instrument: null,
    );

    expect(header['instrument'], isNull);
  });

  test('every take says what to do at the instrument', () {
    for (final take in TransportTake.values) {
      expect(take.label, isNotEmpty);
      expect(take.protocol, isNotEmpty);
      expect(take.id, take.name);
    }
  });
}
