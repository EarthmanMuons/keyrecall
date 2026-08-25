import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The click that sounds the count-in.
///
/// Generated rather than played from an asset, so the app carries no audio
/// files and the click can follow whatever tempo an exercise asks for. It also
/// keeps the sound on the same engine anything else will eventually use, which
/// matters if the pulse ever has to share a clock with performance timing.
///
/// Best effort. A device that will not give us an audio engine leaves the
/// count-in silent, which is exactly where it was before, rather than failing
/// an attempt.
final countInClickerProvider = Provider<CountInClicker>((ref) {
  final clicker = CountInClicker();
  ref.onDispose(clicker.dispose);
  return clicker;
});

class CountInClicker {
  /// Frames per second. 44.1kHz is what every platform accepts without
  /// resampling.
  static const int _sampleRate = 44100;

  /// How long one click lasts. Short enough to read as a tick rather than a
  /// note, long enough to hear on a phone speaker.
  static const Duration _clickLength = Duration(milliseconds: 40);

  /// The downbeat sits a fifth above the others, which is enough to hear
  /// "one" without a second sound.
  static const double _beatHz = 880;
  static const double _downbeatHz = 1320;

  /// Silence handed to the engine when nothing is due, so it has something to
  /// play rather than running dry between beats.
  static const int _silenceFrames = 2048;

  final List<Int16List> _queued = [];
  bool _ready = false;
  bool _unavailable = false;

  /// Prepares the engine, if this device has one to give.
  Future<void> prepare() async {
    if (_ready || _unavailable) return;
    try {
      FlutterPcmSound.setFeedCallback((_) => unawaited(_feed()));
      await FlutterPcmSound.setLogLevel(LogLevel.none);
      await FlutterPcmSound.setup(
        sampleRate: _sampleRate,
        channelCount: 1,
        iosAudioCategory: IosAudioCategory.playback,
      );
      await FlutterPcmSound.setFeedThreshold(_silenceFrames);
      _ready = true;
      FlutterPcmSound.start();
    } on Object catch (error) {
      // A simulator without audio, a test binding with no plugins, a device
      // that refuses the category: all of them mean no click, and none of them
      // mean the attempt cannot proceed.
      _unavailable = true;
      if (kDebugMode) debugPrint('[audio] no count-in click: $error');
    }
  }

  /// Sounds one beat of the count-in.
  void beat({bool downbeat = false}) {
    if (!_ready) {
      unawaited(prepare());
      return;
    }
    _queued.add(_click(downbeat ? _downbeatHz : _beatHz));
  }

  /// Stops and releases the engine.
  Future<void> dispose() async {
    _queued.clear();
    if (!_ready) return;
    _ready = false;
    FlutterPcmSound.setFeedCallback(null);
    await FlutterPcmSound.release();
  }

  Future<void> _feed() async {
    if (!_ready) return;
    final frames = _queued.isEmpty
        ? Int16List(_silenceFrames)
        : _queued.removeAt(0);
    try {
      await FlutterPcmSound.feed(
        PcmArrayInt16(bytes: ByteData.sublistView(frames)),
      );
    } on Object {
      _ready = false;
      _unavailable = true;
    }
  }

  /// A sine burst that decays to nothing, so it reads as a tick rather than a
  /// tone and never clicks on its own edges.
  static Int16List _click(double hz) {
    final length = _clickLength.inMicroseconds * _sampleRate ~/ 1000000;
    final frames = Int16List(length);
    for (var i = 0; i < length; i++) {
      final t = i / _sampleRate;
      final decay = math.exp(-t * 60);
      frames[i] = (math.sin(2 * math.pi * hz * t) * decay * 12000).round();
    }
    return frames;
  }
}
