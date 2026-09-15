import 'dart:async';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

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

  group('what it reports having handed over', () {
    /// A count-in of four at 750 ms is three and a half seconds of audio,
    /// which the engine takes a second at a time.
    Future<PulseClicker> countIn(_RecordingSink sink) async {
      final clicker = PulseClicker(sink: sink);
      await clicker.play(
        countInBeats: 4,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );
      return clicker;
    }

    test('counts only the beats the engine has taken so far', () async {
      final sink = _RecordingSink();
      final clicker = await countIn(sink);

      expect(
        clicker.delivered.deliveredBeats,
        lessThan(4),
        reason:
            'one chunk is a second of a three-second count-in, and the '
            'rest has not been offered yet',
      );
      expect(clicker.delivered.delivery, ChannelDelivery.partial);
      await clicker.stop();
    });

    test('is complete once the whole pulse has been taken', () async {
      final sink = _RecordingSink();
      final clicker = await countIn(sink);
      for (var chunk = 0; chunk < 4; chunk++) {
        sink.requestFrames();
        await Future<void>.delayed(Duration.zero);
      }

      expect(clicker.delivered.deliveredBeats, 4);
      expect(clicker.delivered.delivery, ChannelDelivery.complete);
      expect(clicker.delivered.failureReason, isNull);
      await clicker.stop();
    });

    test('a device with no engine took none of it', () async {
      final clicker = PulseClicker(sink: _RefusingSink());
      await clicker.play(
        countInBeats: 4,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );

      expect(clicker.delivered.delivery, ChannelDelivery.unavailable);
      expect(clicker.delivered.deliveredBeats, 0);
      expect(clicker.delivered.failureReason, contains('no audio'));
      await clicker.stop();
    });

    test('keeps what was taken when a later chunk fails', () async {
      final sink = _FailingAfterFirstFeedSink();
      final clicker = PulseClicker(sink: sink);
      await clicker.play(
        countInBeats: 4,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );
      final afterFirst = clicker.delivered.deliveredBeats;
      sink.requestFrames();
      await Future<void>.delayed(Duration.zero);

      expect(afterFirst, greaterThan(0));
      expect(
        clicker.delivered.deliveredBeats,
        afterFirst,
        reason: 'a failure later does not unqueue what the engine already took',
      );
      expect(clicker.delivered.delivery, ChannelDelivery.partial);
      await clicker.stop();
    });

    test('a count-in the attempt ended before it opened', () async {
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
      final delivery = await playing;
      await stopping;

      expect(delivery.deliveredBeats, 0);
    });
  });

  test('reopening waits for queued audio to flush', () async {
    final sink = _DelayedFeedSink();
    final clicker = PulseClicker(sink: sink);
    final playing = clicker.play(
      countInBeats: 4,
      continuingBeats: 0,
      beat: const Duration(milliseconds: 750),
    );
    await sink.feedStarted.future;

    final stopping = clicker.stop();
    final preparing = clicker.prepare();
    await Future<void>.delayed(Duration.zero);

    expect(sink.releaseCalls, 0);
    expect(sink.prepareCalls, 1);

    sink.completeFeed();
    await Future.wait([playing, stopping, preparing]);

    expect(sink.releaseCalls, 1);
    expect(sink.prepareCalls, 2);
    await clicker.stop();
  });

  group('a feed that completes late', () {
    /// Plays a count-in whose chunks are handed over only when the test says.
    Future<PulseClicker> started(_GatedSink sink) async {
      final clicker = PulseClicker(sink: sink);
      final playing = clicker.play(
        countInBeats: 4,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );
      await Future<void>.delayed(Duration.zero);
      sink.complete(0);
      await playing;
      return clicker;
    }

    test('still counts once stopping has begun', () async {
      final sink = _GatedSink();
      final clicker = await started(sink);
      final accepted = clicker.delivered.deliveredBeats;
      expect(accepted, greaterThan(0));

      sink.requestFrames();
      await Future<void>.delayed(Duration.zero);
      final stopping = clicker.stop();
      sink.complete(1);
      await stopping;

      expect(
        clicker.delivered.deliveredBeats,
        greaterThanOrEqualTo(accepted),
        reason:
            'silencing a pulse cannot unaccept frames the engine already took',
      );
    });

    test('keeps what was accepted when it fails after stopping', () async {
      final sink = _GatedSink();
      final clicker = await started(sink);
      final accepted = clicker.delivered.deliveredBeats;

      sink.requestFrames();
      await Future<void>.delayed(Duration.zero);
      final stopping = clicker.stop();
      sink.fail(1);
      await stopping;

      expect(clicker.delivered.deliveredBeats, accepted);
      expect(clicker.delivered.delivery, ChannelDelivery.partial);
    });

    test('does not touch the pulse that replaced it', () async {
      final sink = _GatedSink();
      final clicker = await started(sink);
      sink.requestFrames();
      await Future<void>.delayed(Duration.zero);

      // A second pulse on the same clicker, while the first one's chunk is
      // still out. Nothing of this one has been handed over yet.
      final playing = clicker.play(
        countInBeats: 4,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );
      await playing;
      final before = clicker.delivered;
      expect(before.deliveredBeats, 0);

      sink.complete(1);
      await Future<void>.delayed(Duration.zero);

      expect(
        clicker.delivered,
        before,
        reason:
            'that chunk was audio the pulse before this one asked for, and '
            'this one has still had nothing handed over',
      );
      sink.complete(2);
      await clicker.stop();
    });

    test('never lets a pulse report fewer beats than it already had', () async {
      final sink = _GatedSink();
      final clicker = await started(sink);
      var highest = clicker.delivered.deliveredBeats;

      for (var chunk = 1; chunk < 4; chunk++) {
        sink.requestFrames();
        await Future<void>.delayed(Duration.zero);
        sink.complete(chunk);
        await Future<void>.delayed(Duration.zero);
        expect(clicker.delivered.deliveredBeats, greaterThanOrEqualTo(highest));
        highest = clicker.delivered.deliveredBeats;
      }
      await clicker.stop();
      expect(clicker.delivered.deliveredBeats, greaterThanOrEqualTo(highest));
    });
  });
}

/// An engine that takes a chunk only when the test hands it over.
class _GatedSink implements PulseAudioSink {
  void Function(int)? _onFeed;
  final List<Completer<void>> _feeds = [];

  void requestFrames() => _onFeed?.call(0);

  void complete(int chunk) {
    if (chunk < _feeds.length && !_feeds[chunk].isCompleted) {
      _feeds[chunk].complete();
    }
  }

  void fail(int chunk) {
    if (chunk < _feeds.length && !_feeds[chunk].isCompleted) {
      _feeds[chunk].completeError(StateError('the engine stopped taking it'));
    }
  }

  @override
  void setFeedCallback(void Function(int)? callback) => _onFeed = callback;

  @override
  Future<void> prepare({
    required int sampleRate,
    required int feedThreshold,
  }) async {}

  @override
  Future<void> feed(PcmArrayInt16 frames) {
    final completer = Completer<void>();
    _feeds.add(completer);
    return completer.future;
  }

  @override
  Future<void> release() async {}
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

/// Takes the first chunk and refuses everything after it.
class _FailingAfterFirstFeedSink implements PulseAudioSink {
  void Function(int)? _onFeed;
  int feeds = 0;

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
    if (feeds++ > 0) throw StateError('the engine stopped taking frames');
  }

  @override
  Future<void> release() async {}
}

class _RefusingSink implements PulseAudioSink {
  @override
  void setFeedCallback(void Function(int)? callback) {}

  @override
  Future<void> prepare({
    required int sampleRate,
    required int feedThreshold,
  }) async => throw StateError('no audio on this device');

  @override
  Future<void> feed(PcmArrayInt16 frames) async {}

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

class _DelayedFeedSink implements PulseAudioSink {
  final feedStarted = Completer<void>();
  final _fed = Completer<void>();
  int prepareCalls = 0;
  int releaseCalls = 0;

  void completeFeed() => _fed.complete();

  @override
  void setFeedCallback(void Function(int)? callback) {}

  @override
  Future<void> prepare({
    required int sampleRate,
    required int feedThreshold,
  }) async => prepareCalls++;

  @override
  Future<void> feed(PcmArrayInt16 frames) async {
    feedStarted.complete();
    await _fed.future;
  }

  @override
  Future<void> release() async => releaseCalls++;
}
