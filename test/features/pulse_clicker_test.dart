import 'dart:async';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/audio/pulse_clicker.dart';

void main() {
  test('queues each frame of a count-in exactly once', () async {
    final sink = _RecordingSink();
    final clicker = PulseClicker(sink: sink);

    await clicker.play(
      countInBeats: 4,
      continuingBeats: 0,
      beat: const Duration(milliseconds: 750),
    );
    for (var index = 0; index < 4; index++) {
      sink.requestFrames();
      await Future<void>.delayed(Duration.zero);
    }

    expect(sink.sentFrames, sink.declaredFrames);
    expect(sink.largestBuffer, lessThanOrEqualTo(44100));

    await clicker.stop();
  });

  test('preparation is single-flight', () async {
    final sink = _DelayedSink();
    final clicker = PulseClicker(sink: sink);

    final first = clicker.prepare();
    final second = clicker.prepare();
    await sink.started.future;

    expect(sink.prepareCalls, 1);
    sink.completePreparation();
    await Future.wait([first, second]);
    await clicker.stop();
  });

  test('stopping during preparation prevents playback', () async {
    final sink = _DelayedSink();
    final clicker = PulseClicker(sink: sink);
    final playing = clicker.play(
      countInBeats: 4,
      continuingBeats: 0,
      beat: const Duration(milliseconds: 750),
    );
    await sink.started.future;

    final stopping = clicker.stop();
    sink.completePreparation();
    await Future.wait([playing, stopping]);

    expect(sink.feedCalls, 0);
    expect(sink.releaseCalls, 1);
    expect(sink.hasFeedCallback, isFalse);
  });
}

class _RecordingSink implements PulseAudioSink {
  void Function(int)? _onFeed;
  int declaredFrames = 0;
  int sentFrames = 0;
  int largestBuffer = 0;

  void requestFrames() => _onFeed!(0);

  @override
  void setFeedCallback(void Function(int)? callback) => _onFeed = callback;

  @override
  Future<void> prepare({
    required int sampleRate,
    required int feedThreshold,
  }) async {}

  @override
  Future<void> feed(PcmArrayInt16 frames) async {
    final bufferedFrames = frames.bytes.buffer.lengthInBytes ~/ 2;
    declaredFrames += frames.count;
    sentFrames += bufferedFrames;
    largestBuffer = largestBuffer > bufferedFrames
        ? largestBuffer
        : bufferedFrames;
  }

  @override
  Future<void> release() async {}
}

class _DelayedSink implements PulseAudioSink {
  final started = Completer<void>();
  final _prepared = Completer<void>();
  void Function(int)? _onFeed;
  int prepareCalls = 0;
  int feedCalls = 0;
  int releaseCalls = 0;

  bool get hasFeedCallback => _onFeed != null;

  void completePreparation() => _prepared.complete();

  @override
  void setFeedCallback(void Function(int)? callback) => _onFeed = callback;

  @override
  Future<void> prepare({
    required int sampleRate,
    required int feedThreshold,
  }) async {
    prepareCalls++;
    if (!started.isCompleted) started.complete();
    await _prepared.future;
  }

  @override
  Future<void> feed(PcmArrayInt16 frames) async => feedCalls++;

  @override
  Future<void> release() async => releaseCalls++;
}
