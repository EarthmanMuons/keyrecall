import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

/// The click that sounds the pulse.
///
/// Generated rather than played from an asset, so the app carries no audio
/// files and the click follows whatever tempo an exercise asks for. It sounds
/// on the shared audio engine, which is what a pulse sharing a clock with
/// performance timing would need.
///
/// Best effort: a device that will not give us an audio engine leaves the
/// count-in silent rather than failing an attempt. [PulseClicker.delivered]
/// says so rather than swallowing it, because an attempt that was supplied no
/// pulse did not run under the tempo support it was resolved to have.
final pulseClickerProvider = Provider<PulseClicker>((ref) {
  final clicker = PulseClicker();
  ref.onDispose(clicker.stop);
  return clicker;
});

abstract interface class PulseAudioSink {
  /// Sets the callback that asks for more queued frames.
  void setFeedCallback(void Function(int)? callback);

  /// Opens the output at [sampleRate] and requests refills at [feedThreshold].
  Future<void> prepare({required int sampleRate, required int feedThreshold});

  /// Queues [frames] for playback.
  Future<void> feed(PcmArrayInt16 frames);

  /// Closes the output and discards queued frames.
  Future<void> release();
}

class _FlutterPcmSoundSink implements PulseAudioSink {
  @override
  void setFeedCallback(void Function(int)? callback) {
    FlutterPcmSound.setFeedCallback(callback);
  }

  @override
  Future<void> prepare({
    required int sampleRate,
    required int feedThreshold,
  }) async {
    await FlutterPcmSound.setLogLevel(LogLevel.none);
    await FlutterPcmSound.setup(
      sampleRate: sampleRate,
      channelCount: 1,
      iosAudioCategory: IosAudioCategory.playback,
    );
    await FlutterPcmSound.setFeedThreshold(feedThreshold);
  }

  @override
  Future<void> feed(PcmArrayInt16 frames) => FlutterPcmSound.feed(frames);

  @override
  Future<void> release() => FlutterPcmSound.release();
}

class PulseClicker {
  PulseClicker({PulseAudioSink? sink}) : _sink = sink ?? _FlutterPcmSoundSink();

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

  /// The track currently refillable, and nothing if none is.
  ///
  /// One object rather than a track beside a cursor beside a pulse: a refill
  /// takes its bytes and the identity it submits them under from the same
  /// place, so it cannot hand over one playback's audio stamped as another's.
  _InstalledTrack? _installed;
  final PulseAudioSink _sink;
  bool _ready = false;
  bool _opened = false;
  bool _unavailable = false;
  String? _silence;
  TempoDelivery _delivered = TempoDelivery.notRequested();

  /// The pulse being handed over: how many beats it holds, how long each one
  /// is in frames, and how many of them were already behind the cursor when
  /// the engine opened.
  int _pulseBeats = 0;
  int _pulseBeatFrames = 1;
  int _pulseSkipped = 0;

  /// Which pulse is current, counted up by [play].
  ///
  /// Not [_generation], which counts stops. A pulse that is being silenced is
  /// still the pulse whose frames the sink took, so a feed completing during
  /// the teardown belongs to it and is counted; a feed completing after the
  /// next pulse has started belongs to neither and is dropped.
  int _pulse = 0;

  /// How far into the track the sink has actually accepted.
  ///
  /// Kept apart from [_fed], which is a scheduling cursor that [stop] is free
  /// to reset. This is accounting for something that already happened, so it
  /// only ever moves forward within a pulse, and silencing a pulse cannot
  /// unaccept frames the engine took.
  int _acceptedFrames = 0;
  int _generation = 0;
  Future<void>? _preparing;
  Future<void>? _stopping;
  Future<void>? _feeding;
  Timer? _release;

  /// What the pulse this clicker was last asked for has handed over so far.
  ///
  /// Readable without waiting, because an attempt ends when the learner ends
  /// it and must not be held open for an audio engine to finish answering. It
  /// moves only forward within one pulse: nothing is queued until the engine
  /// opens, and a beat the engine accepted stays counted even if a later chunk
  /// fails.
  ///
  /// A queued beat is one the audio layer took, not one anybody is known to
  /// have heard. The sink says it accepted the frames and nothing on this path
  /// reports back from the speaker, so this is the strongest claim available:
  /// the app supplied it.
  TempoDelivery get delivered => _delivered;

  /// Prepares the engine, if this device has one to give.
  ///
  /// Cheap to call again: the engine is released after each count-in, so this
  /// is what brings it back for the next one.
  Future<void> prepare() async {
    // Taken before the wait, not after it. Waking up later must not make this
    // the current preparation: the stop it is queued behind may itself have
    // been the thing that cancelled it, and adopting the generation that
    // cancellation created is how a silenced pulse came back to life.
    final generation = _generation;
    final stopping = _stopping;
    if (stopping != null) await stopping;
    if (generation != _generation) return;
    if (_ready || _unavailable) return;
    final pending = _preparing;
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _prepare(generation).whenComplete(() {
      if (identical(_preparing, operation)) _preparing = null;
    });
    _preparing = operation;
    await operation;
  }

  Future<void> _prepare(int generation) async {
    try {
      // Only ever the rest of a pulse that is already playing. With no track
      // there is nothing to hand over: the engine stops itself when its queue
      // empties, and feeding it silence to keep it awake only makes it stop
      // and restart a few dozen times a second.
      _sink.setFeedCallback((_) => unawaited(_feedNext()));
      await _sink.prepare(
        sampleRate: _sampleRate,
        // Asked for more while half a chunk is still queued, so the queue is
        // never empty between chunks. Draining to nothing is what makes the
        // engine stop and restart, and every one of those is an audible seam.
        feedThreshold: _chunkFrames ~/ 2,
      );
      // Before the generation check: a preparation that went stale still
      // opened the engine, and only _opened tells _stop to release it.
      _opened = true;
      if (generation != _generation) return;
      _ready = true;
    } on Object catch (error) {
      // A simulator without audio, a test binding with no plugins, a device
      // that refuses the category: all of them mean no click, and none of them
      // mean the attempt cannot proceed.
      if (generation == _generation) _unavailable = true;
      _silence = '$error';
      _sink.setFeedCallback(null);
      if (kDebugMode) debugPrint('[audio] no count-in click: $error');
    }
  }

  /// Sounds [countInBeats] counting beats and then [continuingBeats] more,
  /// [beat] apart, starting now.
  ///
  /// Pass zero continuing beats for a count-in that stops and leaves the
  /// learner holding the pulse.
  ///
  /// The whole thing is rendered on one sample clock, then queued in chunks
  /// before the engine runs dry between them.
  ///
  /// One sample clock means the beats cannot drift against each other however
  /// busy the app is.
  ///
  /// How much of it the engine took is [delivered], which goes on moving as
  /// the engine asks for the rest. A beat the engine was too slow to reach is
  /// dropped rather than played late, and a dropped beat is one the learner
  /// was never supplied.
  Future<TempoDelivery> play({
    required int countInBeats,
    required int continuingBeats,
    required Duration beat,
  }) async {
    // Preparing the engine takes a variable few hundred milliseconds, and the
    // count-in the learner is watching has already started. Rather than
    // holding the numbers back, the audio starts from wherever the count-in
    // has got to, dropping the beats it missed instead of playing them late.
    final since = Stopwatch()..start();
    final beats = countInBeats + continuingBeats;
    // This playback's identity, taken before it waits on anything. Every
    // continuation below proves it still holds both before touching playback
    // state: a pulse that resumed later does not thereby become the current
    // one, whether it was replaced by another play or silenced by a stop.
    final generation = _generation;
    final pulse = ++_pulse;
    // Detached before this waits on anything. From here until this playback
    // installs its own track there is nothing to refill from, so a callback
    // arriving in that gap cannot hand over the audio of the playback this one
    // just replaced.
    _installed = null;
    // Every figure this pulse is accounted against, established in one step
    // with the pulse itself, so no window exists where one of them describes
    // this playback and another still describes the one before it. Nothing has
    // been handed over until the engine takes some of it, which is what it
    // reports while it is opening.
    final beatFrames = beat.inMicroseconds * _sampleRate ~/ 1000000;
    _pulseBeats = beats;
    _pulseBeatFrames = beatFrames;
    _pulseSkipped = 0;
    _acceptedFrames = 0;
    _delivered = TempoDelivery.silent(beats, reason: 'the engine is opening');
    await prepare();
    // Nothing below may run for a pulse that is no longer the one on screen:
    // installing a track, arming the release, and handing audio over are all
    // this playback acting, and it has been cancelled or replaced.
    if (!_owns(pulse, generation)) return _cancelled(beats);
    if (!_ready) {
      return _delivered = TempoDelivery.silent(
        beats,
        reason: _silence ?? 'no audio engine',
      );
    }

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
    final startFrame = (since.elapsedMicroseconds * _sampleRate ~/ 1000000)
        .clamp(0, track.length);
    _installed = _InstalledTrack(pulse: pulse, frames: track, fed: startFrame);
    // A beat is lost only once its whole click is behind the cursor. Opening
    // the engine a millisecond into the first click clips it inaudibly, and
    // counting that as a beat nobody heard would report a shortfall that is
    // not one.
    _pulseSkipped = startFrame <= _clickFrames
        ? 0
        : (startFrame - _clickFrames) ~/ beatFrames + 1;

    // Released once the tail has played out, by which point the engine has
    // already stopped itself. Tearing it down while it is still sounding is
    // what the last stray click was.
    _release?.cancel();
    _release = Timer(beat * beats + _tail * 2, stop);

    await _feedNext();
    // Only the first chunk has been handed over by now; the engine asks for
    // the rest as it plays, and each one that lands moves this on. What the
    // attempt records is read when it closes, not here.
    return _owns(pulse, generation) ? _delivered : _cancelled(beats);
  }

  /// Whether this playback is still the one the clicker is running.
  ///
  /// Two questions, because being replaced by another pulse and being silenced
  /// are different events that both end a playback's claim on the engine.
  bool _owns(int pulse, int generation) =>
      pulse == _pulse && generation == _generation;

  /// What a playback that never got to sound reports.
  ///
  /// Its own report rather than whatever [delivered] now holds, which belongs
  /// to the pulse that replaced it.
  TempoDelivery _cancelled(int beats) =>
      TempoDelivery.silent(beats, reason: 'the pulse ended before it sounded');

  /// Notes how much of the pulse the engine has taken.
  ///
  /// Only ever forward. A chunk that failed leaves the beats already accepted
  /// counted, because they were: a later failure does not unqueue them, and
  /// reporting the whole pulse as silent would lose the difference between an
  /// engine that never opened and one that stopped partway.
  void _recordQueued({String? failure}) {
    if (_pulseBeats == 0) return;
    final through = _acceptedFrames < _clickFrames
        ? 0
        : (_acceptedFrames - _clickFrames) ~/ _pulseBeatFrames + 1;
    final queued = (through - _pulseSkipped).clamp(0, _pulseBeats);
    _delivered = TempoDelivery(
      requestedBeats: _pulseBeats,
      deliveredBeats: queued,
      failureReason: switch (queued) {
        _ when failure != null => failure,
        _ when queued == _pulseBeats => null,
        0 => 'the engine took none of the pulse',
        _ => 'the engine took $queued of $_pulseBeats beats',
      },
    );
  }

  /// Silences the pulse and releases the engine.
  ///
  /// Public because an attempt can end before its last beat, and a metronome
  /// still ticking over a finished attempt is the app talking over the learner.
  ///
  /// Resets scheduling and nothing else. What the sink already accepted is a
  /// fact about an attempt that has happened, and silencing what is left of a
  /// pulse cannot make it un-happen; an attempt closing after this reads the
  /// same delivery it would have read before.
  Future<void> stop() async {
    _generation++;
    _release?.cancel();
    _release = null;
    _installed = null;
    _ready = false;
    _sink.setFeedCallback(null);
    final pending = _stopping;
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _stop().whenComplete(() {
      if (identical(_stopping, operation)) _stopping = null;
    });
    _stopping = operation;
    await operation;
  }

  Future<void> _stop() async {
    final preparing = _preparing;
    if (preparing != null) await preparing;
    final feeding = _feeding;
    if (feeding != null) await feeding;
    if (!_opened) return;
    _opened = false;
    try {
      await _sink.release();
    } on Object {
      // Nothing useful to do about a device that will not let go.
    }
  }

  static int get _chunkFrames => _chunk.inMicroseconds * _sampleRate ~/ 1000000;

  static int get _clickFrames =>
      _clickLength.inMicroseconds * _sampleRate ~/ 1000000;

  /// Hands over the next chunk, or nothing once the pulse has all been given.
  ///
  /// One at a time. The engine asks for more from a callback, and the cursor
  /// moves before the handover completes, so two overlapping calls would take
  /// different chunks and could hand them over in either order. Whether that
  /// can happen depends on the plugin's callback timing, which is not
  /// something to leave to chance in the one place where order is the audio.
  Future<void> _feedNext() async {
    if (!_ready || _feeding != null) return;
    // Bytes and identity from one object, read together. A track and a pulse
    // counter read separately can disagree, and did: a refill arriving while a
    // new playback was opening the engine took the old track and submitted it
    // as the new one's audio.
    final installed = _installed;
    if (installed == null || installed.fed >= installed.frames.length) return;

    final end = math.min(installed.fed + _chunkFrames, installed.frames.length);
    final frames = Int16List.fromList(
      Int16List.sublistView(installed.frames, installed.fed, end),
    );
    installed.fed = end;
    final pulse = installed.pulse;
    late final Future<void> operation;
    operation = _feed(frames, pulse: pulse, through: end).whenComplete(() {
      if (identical(_feeding, operation)) _feeding = null;
    });
    _feeding = operation;
    await operation;
  }

  Future<void> _feed(
    Int16List frames, {
    required int pulse,
    required int through,
  }) async {
    if (!_ready) return;
    try {
      await _sink.feed(PcmArrayInt16(bytes: ByteData.sublistView(frames)));
      // Only ever forward, and only for the pulse this chunk came from. A
      // completion that arrives after the next pulse has started describes
      // audio that pulse never asked for.
      if (pulse != _pulse) return;
      _acceptedFrames = math.max(_acceptedFrames, through);
      _recordQueued();
    } on Object catch (error) {
      // Before anything shared moves. A chunk belonging to a pulse that has
      // been replaced says nothing about the engine the replacement is using,
      // and closing that engine here would silence a pulse whose own audio was
      // being taken perfectly well.
      if (pulse != _pulse) return;
      _ready = false;
      _unavailable = true;
      _silence = '$error';
      // Nothing to unaccept: this chunk never advanced the accepted position,
      // so what the sink already took stays counted.
      _recordQueued(failure: '$error');
    }
  }

  /// Writes a sine burst that decays to nothing, so it reads as a tick rather
  /// than a tone and never clicks on its own edges.
  static void _writeClick(
    Int16List track, {
    required int at,
    required double hz,
  }) {
    for (var i = 0; i < _clickFrames && at + i < track.length; i++) {
      final t = i / _sampleRate;
      final decay = math.exp(-t * 60);
      track[at + i] = (math.sin(2 * math.pi * hz * t) * decay * 12000).round();
    }
  }
}

/// A rendered pulse and how far into it the engine has been fed, held together
/// with the playback it belongs to.
class _InstalledTrack {
  _InstalledTrack({
    required this.pulse,
    required this.frames,
    required this.fed,
  });

  /// Which playback rendered these frames.
  final int pulse;

  final Int16List frames;

  /// How far the engine has been offered, in frames.
  int fed;
}
