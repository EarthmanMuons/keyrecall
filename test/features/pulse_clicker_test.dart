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
