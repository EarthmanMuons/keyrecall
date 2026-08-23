import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_input_sources/keyrecall_input_sources.dart';

import 'demo_input_notifier.dart';

/// The synthetic instrument, as a normalized event stream.
///
/// Turns "here is what the instrument is doing now" into ordered events by
/// diffing against what it was doing before. Only held keys produce note-ons
/// and note-offs; a note the pedal is holding produced its note-off when the
/// key came up, so lifting the pedal is reported by the pedal event alone.
/// That is what a real instrument sends, and matching it is the whole point of
/// having a synthetic one.
///
/// Vendored from WhatChord's demo temporal events provider. Its version
/// diffed a single sounding-note set and repaired the result with a reset,
/// because a set that cannot distinguish a held note from a sustained one
/// makes an ordinary release look like a note vanishing. Modeling the two
/// separately removes the need for the repair: every transition this can
/// produce is one a keyboard can produce.
final demoTemporalEventsProvider =
    Provider.autoDispose<Stream<InputTemporalEvent>>((ref) {
      // A single-subscription controller buffers the opening reset until the
      // selected input stream subscribes, so the initial snapshot and the
      // events that follow it cannot race.
      final controller = StreamController<InputTemporalEvent>(sync: true);
      final clock = ref.watch(inputEventClockProvider);
      var previous = ref.read(demoInputProvider);

      ref.listen<DemoInputState>(demoInputProvider, (_, next) {
        if (previous.isPedalDown != next.isPedalDown) {
          controller.add(
            InputTemporalPedalEvent(
              timestampMs: clock(),
              down: next.isPedalDown,
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
          controller.add(
            InputTemporalNoteOffEvent(
              timestampMs: clock(),
              noteNumber: note,
              velocity: 0,
            ),
          );
        }
        for (final note in struck) {
          controller.add(
            InputTemporalNoteOnEvent(
              timestampMs: clock(),
              noteNumber: note,
              velocity: 100,
            ),
          );
        }
        previous = next;
      });

      controller.add(
        InputTemporalResetEvent(
          timestampMs: clock(),
          snapshot: InputTemporalSnapshot(
            pressedNoteNumbers: previous.pressedNoteNumbers,
            sustainedNoteNumbers: previous.sustainedNoteNumbers,
            pedalDown: previous.isPedalDown,
          ),
        ),
      );

      ref.onDispose(() async {
        await controller.close();
      });
      return controller.stream;
    });
