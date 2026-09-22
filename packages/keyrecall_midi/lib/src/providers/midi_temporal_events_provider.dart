import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'midi_input_notifier.dart';

/// The adopted instrument's playing, as the normalized product stream.
///
/// A thin view of [midiInputProvider]: the reducer there decides what the
/// input means, and this only delivers it. Nothing here normalizes, tracks
/// what is sounding, or interprets a failure, because a second interpretation
/// is exactly how two of them came to disagree.
final midiTemporalEventsProvider =
    Provider.autoDispose<Stream<InputTemporalEvent>>((ref) {
      // A single-subscription controller buffers the opening reset until the
      // selected input StreamProvider subscribes. This closes the otherwise
      // possible gap between reading the snapshot and attaching the listener.
      final controller = StreamController<InputTemporalEvent>(sync: true);
      final input = ref.watch(midiInputProvider.notifier);

      final subscription = input.events.listen(
        controller.add,
        onError: controller.addError,
      );
      controller.add(input.openObservation());

      ref.onDispose(() async {
        await subscription.cancel();
        await controller.close();
      });
      return controller.stream;
    });
