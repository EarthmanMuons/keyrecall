import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_input_sources/keyrecall_input_sources.dart';

import 'demo_input_notifier.dart';

/// The synthetic instrument, named as a source like any other.
const _demoSource = InputSourceIdentity(
  deviceId: 'demo',
  transport: 'synthetic',
);

/// The synthetic instrument, as a normalized event stream.
///
/// Turns "here is what the instrument is doing now" into raw messages by
/// diffing against what it was doing before, and hands them to the same
/// [InputReducer] a real instrument's messages go through. Nothing about the
/// normalized stream is reimplemented here, which is what makes the synthetic
/// source a genuine stand-in rather than a second interpretation that happens
/// to agree today.
///
/// Only held keys produce note-ons and note-offs: a note the pedal is holding
/// produced its note-off when the key came up, so lifting the pedal is
/// reported by the pedal event alone, which is what a real instrument sends.
final demoTemporalEventsProvider =
    Provider.autoDispose<Stream<InputTemporalEvent>>((ref) {
      // A single-subscription controller buffers the opening reset until the
      // selected input stream subscribes, so the initial snapshot and the
      // events that follow it cannot race.
      final controller = StreamController<InputTemporalEvent>(sync: true);
      final clock = ref.watch(inputEventClockProvider);
      final reducer = InputReducer()..adopt(_demoSource);
      var previous = ref.read(demoInputProvider);

      void feed(RawInputMessage message) {
        for (final event in reducer.receive(
          RawInputEnvelope(
            source: _demoSource,
            message: message,
            arrivalTimestampMs: clock(),
          ),
        )) {
          controller.add(event);
        }
      }

      ref.listen<DemoInputState>(demoInputProvider, (_, next) {
        if (previous.isPedalDown != next.isPedalDown) {
          feed(
            RawInputMessage(
              kind: RawInputKind.sustain,
              sustainValue: next.isPedalDown ? 127 : 0,
            ),
          );
        }

        final released =
            previous.pressedNoteNumbers
                .difference(next.pressedNoteNumbers)
                .toList()
              ..sort();
        final struck =
            next.pressedNoteNumbers
                .difference(previous.pressedNoteNumbers)
                .toList()
              ..sort();

        for (final note in released) {
          feed(
            RawInputMessage(
              kind: RawInputKind.noteOff,
              note: note,
              velocity: 0,
            ),
          );
        }
        for (final note in struck) {
          feed(
            RawInputMessage(
              kind: RawInputKind.noteOn,
              note: note,
              velocity: 100,
            ),
          );
        }
        previous = next;
      });

      for (final event in reducer.begin(timestampMs: clock())) {
        controller.add(event);
      }
      // Whatever was already sounding when the stream opened is the
      // instrument's, not this observation's: it is played back in so the
      // reducer owns it, rather than asserted into the opening snapshot.
      for (final note in previous.pressedNoteNumbers) {
        feed(
          RawInputMessage(kind: RawInputKind.noteOn, note: note, velocity: 100),
        );
      }

      ref.onDispose(() async {
        await controller.close();
      });
      return controller.stream;
    });
