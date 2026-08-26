import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The click that sounds the pulse.
///
/// Generated rather than played from an asset, so the app carries no audio
/// files and the click can follow whatever tempo an exercise asks for. It also
/// keeps the sound on the same engine anything else will eventually use, which
/// matters if the pulse ever has to share a clock with performance timing.
///
/// Best effort. A device that will not give us an audio engine leaves the
/// count-in silent, which is exactly where it was before, rather than failing
/// an attempt.
final pulseClickerProvider = Provider<PulseClicker>((ref) {
  final clicker = PulseClicker();
  ref.onDispose(clicker.stop);
  return clicker;
});

class PulseClicker {
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

  /// Beats between accents. The exercises are one note to a beat in 4/4.
  static const int _beatsPerBar = 4;

  /// Silence past the last click, so the engine reaches the end of its queue
  /// while it is playing nothing.
  static const Duration _tail = Duration(milliseconds: 500);

  /// How much audio is handed over at a time.
  ///
  /// The engine keeps its queue in one buffer and pops played frames off the
  /// front, which costs a copy of everything still waiting. A whole count-in
  /// plus a pulse through a two-octave scale is over three megabytes, and
  /// handing that across in one piece asks the audio thread to move all of it
  /// on every callback. A second at a time keeps that copy small.
  static const Duration _chunk = Duration(seconds: 1);

  /// The pulse being played, and how far into it the engine has been fed.
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
      // Only ever the rest of a pulse that is already playing. With no track
      // there is nothing to hand over: the engine stops itself when its queue
      // empties, and feeding it silence to keep it awake only makes it stop
      // and restart a few dozen times a second.
      FlutterPcmSound.setFeedCallback((_) => unawaited(_feedNext()));
      await FlutterPcmSound.setLogLevel(LogLevel.none);
      await FlutterPcmSound.setup(
        sampleRate: _sampleRate,
        channelCount: 1,
        iosAudioCategory: IosAudioCategory.playback,
      );
      // Asked for more while half a chunk is still queued, so the queue is
      // never empty between chunks. Draining to nothing is what makes the
      // engine stop and restart, and every one of those is an audible seam.
      await FlutterPcmSound.setFeedThreshold(_chunkFrames ~/ 2);
      _ready = true;
    } on Object catch (error) {
      // A simulator without audio, a test binding with no plugins, a device
      // that refuses the category: all of them mean no click, and none of them
      // mean the attempt cannot proceed.
      _unavailable = true;
      if (kDebugMode) debugPrint('[audio] no count-in click: $error');
    }
  }

  /// Sounds [countInBeats] counting beats and then [continuingBeats] more,
  /// [beat] apart, starting now.
  ///
  /// Pass zero continuing beats for a count-in that stops and leaves the
  /// learner holding the pulse.
  ///
  /// The whole thing is rendered and handed over in one piece. Trickling it a
  /// fragment at a time leaves the engine's queue empty between fragments, and
  /// this engine stops itself whenever its queue runs dry: the pulse then
  /// becomes a few dozen starts and stops a second, which is audible at the
  /// seams and puts a click where no beat is.
  ///
  /// One buffer also means the beats are spaced by sample count rather than by
  /// timer, so the pulse cannot drift against itself however busy the app is.
  Future<void> play({
    required int countInBeats,
    required int continuingBeats,
    required Duration beat,
  }) async {
    // Preparing the engine takes a variable few hundred milliseconds, and the
    // count-in the learner is watching has already started. Rather than
    // holding the numbers back, the audio starts from wherever the count-in
    // has got to, dropping the beats it missed instead of playing them late.
    final since = Stopwatch()..start();
    await prepare();
    if (!_ready) return;

    final beats = countInBeats + continuingBeats;
    final beatFrames = beat.inMicroseconds * _sampleRate ~/ 1000000;
    final tailFrames = _tail.inMicroseconds * _sampleRate ~/ 1000000;
    final track = Int16List(beatFrames * beats + tailFrames);
    for (var index = 0; index < beats; index++) {
      _writeClick(
        track,
        at: index * beatFrames,
        // The bar line, not just the start: a pulse that runs through the
        // attempt says where the beat is, and an accent every fourth beat says
        // which beat it is.
        hz: index % _beatsPerBar == 0 ? _downbeatHz : _beatHz,
      );
    }
    _track = track;
    _fed = (since.elapsedMicroseconds * _sampleRate ~/ 1000000).clamp(
      0,
      track.length,
    );

    // Released once the tail has played out, by which point the engine has
    // already stopped itself. Tearing it down while it is still sounding is
    // what the last stray click was.
    _release?.cancel();
    _release = Timer(beat * beats + _tail * 2, stop);

    await _feedNext();
  }

  /// Silences the pulse and releases the engine.
  ///
  /// Public because an attempt can end before its last beat, and a metronome
  /// still ticking over a finished attempt is the app talking over the learner.
  Future<void> stop() async {
    _release?.cancel();
    _release = null;
    _track = null;
    _fed = 0;
    if (!_ready) return;
    _ready = false;
    FlutterPcmSound.setFeedCallback(null);
    try {
      await FlutterPcmSound.release();
    } on Object {
      // Nothing useful to do about a device that will not let go.
    }
  }

  static int get _chunkFrames => _chunk.inMicroseconds * _sampleRate ~/ 1000000;

  /// Hands over the next chunk, or nothing once the pulse has all been given.
  Future<void> _feedNext() async {
    if (!_ready) return;
    final track = _track;
    if (track == null || _fed >= track.length) return;

    final end = math.min(_fed + _chunkFrames, track.length);
    final frames = Int16List.sublistView(track, _fed, end);
    _fed = end;
    await _feed(frames);
  }

  Future<void> _feed(Int16List frames) async {
    if (!_ready) return;
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
