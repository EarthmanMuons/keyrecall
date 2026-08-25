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

  /// How much audio is handed over at a time. Small enough that a count-in
  /// starts promptly, large enough that the engine is never starved.
  static const int _feedFrames = 2048;

  /// The count-in being played, and how far into it the engine has been fed.
  Int16List? _track;
  int _fed = 0;
  bool _ready = false;
  bool _unavailable = false;
  Timer? _release;

  /// Prepares the engine, if this device has one to give.
  ///
  /// Cheap to call again: the engine is released after each count-in, so this
  /// is what brings it back for the next one.
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
      await FlutterPcmSound.setFeedThreshold(_feedFrames);
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

  /// Sounds [beats] beats, [beat] apart, starting now.
  ///
  /// Rendered as one buffer rather than queued a click at a time. Queueing left
  /// the spacing to whenever the engine next asked for data, which is why the
  /// beats did not land on the pulse they were supposed to establish.
  Future<void> playCountIn({required int beats, required Duration beat}) async {
    await prepare();
    if (!_ready) return;

    final beatFrames = beat.inMicroseconds * _sampleRate ~/ 1000000;
    // A tail of silence past the last beat, so the engine is never asked for
    // audio it does not have while the final click is still sounding.
    final track = Int16List(beatFrames * beats + _sampleRate ~/ 4);
    for (var index = 0; index < beats; index++) {
      _writeClick(
        track,
        at: index * beatFrames,
        hz: index == 0 ? _downbeatHz : _beatHz,
      );
    }
    _track = track;
    _fed = 0;

    // The engine lives exactly as long as the count-in. Left running it has to
    // be fed silence forever, and anything that interrupts that feeding leaves
    // it to repeat whatever it last had, which sounds like a metronome that
    // will not stop.
    _release?.cancel();
    _release = Timer(beat * beats + const Duration(seconds: 1), _stop);

    unawaited(_feed());
  }

  /// Stops and releases the engine.
  Future<void> dispose() async {
    _release?.cancel();
    await _stop();
  }

  Future<void> _stop() async {
    _track = null;
    _release = null;
    if (!_ready) return;
    _ready = false;
    FlutterPcmSound.setFeedCallback(null);
    try {
      await FlutterPcmSound.release();
    } on Object {
      // Nothing useful to do about a device that will not let go.
    }
  }

  Future<void> _feed() async {
    if (!_ready) return;
    final track = _track;
    final Int16List frames;
    if (track == null || _fed >= track.length) {
      frames = Int16List(_feedFrames);
    } else {
      final end = math.min(_fed + _feedFrames, track.length);
      frames = Int16List.sublistView(track, _fed, end);
      _fed = end;
    }
    try {
      await FlutterPcmSound.feed(
        PcmArrayInt16(bytes: ByteData.sublistView(frames)),
      );
    } on Object {
      _ready = false;
      _unavailable = true;
    }
  }

  /// Writes a sine burst that decays to nothing, so it reads as a tick rather
  /// than a tone and never clicks on its own edges.
  static void _writeClick(
    Int16List track, {
    required int at,
    required double hz,
  }) {
    final length = _clickLength.inMicroseconds * _sampleRate ~/ 1000000;
    for (var i = 0; i < length && at + i < track.length; i++) {
      final t = i / _sampleRate;
      final decay = math.exp(-t * 60);
      track[at + i] = (math.sin(2 * math.pi * hz * t) * decay * 12000).round();
    }
  }
}
