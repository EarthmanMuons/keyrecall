import 'dart:async';
import 'dart:typed_data';

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

    test(
      'failing stale leaves the engine open under its replacement',
      () async {
        final sink = _GatedSink();
        final clicker = await started(sink);
        sink.requestFrames();
        await Future<void>.delayed(Duration.zero);

        await clicker.play(
          countInBeats: 4,
          continuingBeats: 0,
          beat: const Duration(milliseconds: 750),
        );
        sink.fail(1);
        await Future<void>.delayed(Duration.zero);

        // Not only that the report stayed put: the pulse that replaced it must
        // still be able to hand audio over.
        final taken = sink.accepted;
        sink.requestFrames();
        await Future<void>.delayed(Duration.zero);

        expect(
          sink.accepted,
          greaterThan(taken),
          reason:
              'a chunk from the pulse before this one says nothing about the '
              'engine this one is using',
        );
        sink.complete(2);
        await clicker.stop();
      },
    );

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

  group('a playback queued behind an earlier teardown', () {
    /// Plays once, then leaves a teardown pending so the next play has to
    /// wait behind it.
    Future<PulseClicker> tearingDown(_GatedReleaseSink sink) async {
      final clicker = PulseClicker(sink: sink);
      await clicker.play(
        countInBeats: 4,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );
      unawaited(clicker.stop());
      await Future<void>.delayed(Duration.zero);
      return clicker;
    }

    test('never starts once it has been cancelled', () async {
      final sink = _GatedReleaseSink();
      final clicker = await tearingDown(sink);

      final queued = clicker.play(
        countInBeats: 4,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );
      await Future<void>.delayed(Duration.zero);
      final cancelling = clicker.stop();

      final prepares = sink.prepares;
      final feeds = sink.feeds;
      sink.completeRelease();
      final report = await queued;
      await cancelling;

      expect(
        sink.prepares,
        prepares,
        reason: 'waking up later does not make it the current pulse',
      );
      expect(sink.feeds, feeds);
      expect(report.deliveredBeats, 0);
    });

    test('never starts once another playback has replaced it', () async {
      final sink = _GatedReleaseSink();
      final clicker = await tearingDown(sink);

      final fedBefore = sink.feeds;
      final queued = clicker.play(
        countInBeats: 4,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );
      await Future<void>.delayed(Duration.zero);
      // Not a cancellation: a different pulse, which is its own way of ending
      // this one's claim on the engine.
      final replacing = clicker.play(
        countInBeats: 2,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );

      sink.completeRelease();
      final abandoned = await queued;
      await replacing;

      expect(abandoned.deliveredBeats, 0);
      expect(abandoned.requestedBeats, 4);
      expect(
        sink.feeds - fedBefore,
        1,
        reason:
            'only the pulse that replaced it hands anything over; the one it '
            'replaced woke up to an open engine and must not use it',
      );
      expect(
        clicker.delivered.requestedBeats,
        2,
        reason: 'the pulse that replaced it is the one being reported',
      );
      await clicker.stop();
    });
  });

  group('two playbacks sharing one preparation', () {
    /// The frame the second click of the first chunk starts on, which says
    /// whose pulse the engine was actually given.
    ///
    /// Well past the first click, whose decay crosses the threshold more than
    /// once on the way down.
    int secondClick(_GatedPrepareSink sink) =>
        sink.onsets.firstWhere((frame) => frame > 5000);

    test(
      'hands the engine the pulse that is current, not the one it replaced',
      () async {
        final sink = _GatedPrepareSink();
        final clicker = PulseClicker(sink: sink);

        // No stop anywhere. The second playback simply replaces the first while
        // the engine is still opening, so both wait on the same preparation and
        // both wake up to a ready engine: the stop generation cannot tell them
        // apart, and only the pulse can.
        final replaced = clicker.play(
          countInBeats: 4,
          continuingBeats: 0,
          beat: const Duration(milliseconds: 750),
        );
        await sink.started.future;
        final current = clicker.play(
          countInBeats: 2,
          continuingBeats: 0,
          beat: const Duration(milliseconds: 300),
        );

        sink.completePreparation();
        final abandoned = await replaced;
        await current;

        expect(
          secondClick(sink),
          closeTo(0.3 * 44100, 500),
          reason:
              'a beat of the pulse on screen; at 750 ms it is the abandoned '
              'playback the learner is hearing',
        );
        expect(abandoned.deliveredBeats, 0);
        expect(clicker.delivered.requestedBeats, 2);
        await clicker.stop();
      },
    );
  });

  group('a refill arriving while a new playback is opening', () {
    test('hands over nothing, because no track is installed', () async {
      final sink = _RefillSink();
      final clicker = PulseClicker(sink: sink);
      await clicker.play(
        countInBeats: 4,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 750),
      );
      final submitted = sink.chunks.length;

      // The replacement claims the pulse synchronously and then waits. The
      // engine asks for more inside that wait, when the only track that has
      // ever been installed is the one being replaced.
      final replacing = clicker.play(
        countInBeats: 2,
        continuingBeats: 0,
        beat: const Duration(milliseconds: 300),
      );
      sink.requestFrames();
      final inGap = sink.chunks.length - submitted;
      await replacing;

      expect(
        inGap,
        0,
        reason: 'the replaced playback has no claim on the engine left',
      );
      expect(
        sink.secondClickOf(sink.chunks.length - 1),
        closeTo(0.3 * 44100, 500),
        reason:
            'what was handed over is the audio of the playback that asked '
            'for it, not the one it replaced',
      );
      await clicker.stop();
    });
  });
}

/// An engine that takes a chunk only when the test hands it over.
class _GatedSink implements PulseAudioSink {
  void Function(int)? _onFeed;
  final List<Completer<void>> _feeds = [];

  /// Chunks this sink has been handed, answered or not.
  int get accepted => _feeds.length;

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

/// An engine whose teardown finishes only when the test says.
class _GatedReleaseSink implements PulseAudioSink {
  final _released = Completer<void>();
  int prepares = 0;
  int feeds = 0;

  void completeRelease() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  void setFeedCallback(void Function(int)? callback) {}

  @override
  Future<void> prepare({
    required int sampleRate,
    required int feedThreshold,
  }) async => prepares++;

  @override
  Future<void> feed(PcmArrayInt16 frames) async => feeds++;

  @override
  Future<void> release() => _released.future;
}

/// An engine that opens only when the test says, recording where the clicks
/// of the first chunk it is given fall.
class _GatedPrepareSink implements PulseAudioSink {
  final started = Completer<void>();
  final _prepared = Completer<void>();
  final List<int> onsets = [];
  int feeds = 0;

  void completePreparation() {
    if (!_prepared.isCompleted) _prepared.complete();
  }

  @override
  void setFeedCallback(void Function(int)? callback) {}

  @override
  Future<void> prepare({
    required int sampleRate,
    required int feedThreshold,
  }) async {
    if (!started.isCompleted) started.complete();
    await _prepared.future;
  }

  @override
  Future<void> feed(PcmArrayInt16 frames) async {
    if (feeds++ > 0) return;
    final data = frames.bytes;
    var quiet = true;
    for (var frame = 0; frame * 2 + 1 < data.lengthInBytes; frame++) {
      final loud = data.getInt16(frame * 2, Endian.host).abs() > 500;
      if (loud && quiet) onsets.add(frame);
      quiet = !loud;
    }
  }

  @override
  Future<void> release() async {}
}

/// An engine that accepts everything, asks for more only when the test says,
/// and keeps what it was given.
class _RefillSink implements PulseAudioSink {
  void Function(int)? _onFeed;
  final List<List<int>> chunks = [];

  void requestFrames() => _onFeed?.call(0);

  /// The frame the second click of chunk [index] starts on, well past the
  /// first click, whose decay crosses the threshold on the way down.
  int secondClickOf(int index) =>
      chunks[index].firstWhere((frame) => frame > 5000);

  @override
  void setFeedCallback(void Function(int)? callback) => _onFeed = callback;

  @override
  Future<void> prepare({
    required int sampleRate,
    required int feedThreshold,
  }) async {}

  @override
  Future<void> feed(PcmArrayInt16 frames) async {
    final data = frames.bytes;
    final onsets = <int>[];
    var quiet = true;
    for (var frame = 0; frame * 2 + 1 < data.lengthInBytes; frame++) {
      final loud = data.getInt16(frame * 2, Endian.host).abs() > 500;
      if (loud && quiet) onsets.add(frame);
      quiet = !loud;
    }
    chunks.add(onsets);
  }

  @override
  Future<void> release() async {}
}
