import 'dart:io';
import 'dart:math';

import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_input/keyrecall_input.dart';

const piano = InputSourceIdentity(deviceId: 'piano', transport: 'ble');
const other = InputSourceIdentity(deviceId: 'pad', transport: 'usb');

/// Fixed so every run explores the same streams; a failure names its seed.
const seed = 20260930;

/// Multiplied by `KEYRECALL_SEED_SCALE` for a wider search on demand.
int examples(int count) {
  final value = Platform.environment['KEYRECALL_SEED_SCALE'];
  if (value == null) return count;
  final scale = int.tryParse(value);
  if (scale == null || scale < 1) {
    throw ArgumentError.value(
      value,
      'KEYRECALL_SEED_SCALE',
      'must be a positive integer',
    );
  }
  return count * scale;
}

/// One thing that can happen to a reducer, at [delta] ms after the last.
sealed class Step {
  final int delta;
  const Step(this.delta);
}

final class Deliver extends Step {
  final InputSourceIdentity source;
  final int? channel;
  final RawInputMessage message;

  const Deliver(super.delta, this.source, this.channel, this.message);

  RawInputEnvelope at(int timestampMs) => RawInputEnvelope(
    source: source,
    channel: channel,
    message: message,
    arrivalTimestampMs: timestampMs,
  );

  @override
  String toString() =>
      'Deliver(+$delta, $message${channel == null ? '' : ' ch$channel'}'
      '${source == piano ? '' : ' from $source'})';
}

final class Fail extends Step {
  const Fail(super.delta);

  @override
  String toString() => 'Fail(+$delta)';
}

final class Begin extends Step {
  const Begin(super.delta);

  @override
  String toString() => 'Begin(+$delta)';
}

/// A consumer attaching partway through.
final class Attach extends Step {
  const Attach(super.delta);

  @override
  String toString() => 'Attach(+$delta)';
}

final class Adopt extends Step {
  final InputSourceIdentity? source;

  const Adopt(this.source) : super(0);

  @override
  String toString() => 'Adopt($source)';
}

Arbitrary<T> weighted<T>(List<(int, Arbitrary<T>)> choices) =>
    frequency(choices).map((value) => value as T);

/// Mostly a handful of pitches, so presses, releases, and the pedal collide.
final Arbitrary<int?> anyNote = weighted<int?>([
  (20, integer(min: 60, max: 63)),
  (1, constantFrom<int?>([-1, 128, null])),
]);

final Arbitrary<int?> anyVelocity = weighted<int?>([
  (4, integer(min: 1, max: 127)),
  (2, constant<int?>(0)),
  (1, constantFrom<int?>([-1, 128, null])),
]);

final Arbitrary<int?> anySustain = weighted<int?>([
  (10, constantFrom<int?>([0, 63, 64, 127])),
  (1, constantFrom<int?>([-1, 128, null])),
]);

final Arbitrary<int?> anyChannel = weighted<int?>([
  (10, constantFrom<int?>([null, 0, 1])),
  (1, constantFrom<int?>([-1, 16])),
]);

final Arbitrary<RawInputMessage> anyMessage =
    combine4(
      constantFrom(RawInputKind.values),
      anyNote,
      anyVelocity,
      anySustain,
    ).map(
      (fields) => RawInputMessage(
        kind: fields.$1,
        note: fields.$2,
        velocity: fields.$3,
        sustainValue: fields.$4,
      ),
    );

final Arbitrary<int> anyDelta = weighted<int>([
  (20, integer(min: 0, max: 30)),
  (1, integer(min: -20, max: -1)),
]);

final Arbitrary<Step> anyDelivery = combine4(
  anyDelta,
  weighted<InputSourceIdentity>([(12, constant(piano)), (1, constant(other))]),
  anyChannel,
  anyMessage,
).map<Step>((fields) => Deliver(fields.$1, fields.$2, fields.$3, fields.$4));

final Arbitrary<Step> anyStep = weighted<Step>([
  (40, anyDelivery),
  (1, anyDelta.map<Step>(Fail.new)),
  (1, anyDelta.map<Step>(Begin.new)),
  (1, anyDelta.map<Step>(Attach.new)),
  (1, constantFrom<InputSourceIdentity?>([piano, other, null]).map(Adopt.new)),
]);

/// What a well-formed performance on the adopted piano can send.
final Arbitrary<Step> anyPlaying =
    combine4(
      integer(min: 0, max: 30),
      constantFrom<int?>([null, 0, 1]),
      constantFrom([
        RawInputKind.noteOn,
        RawInputKind.noteOn,
        RawInputKind.noteOff,
        RawInputKind.sustain,
        RawInputKind.allNotesOff,
        RawInputKind.other,
      ]),
      combine3(
        integer(min: 60, max: 63),
        integer(min: 0, max: 127),
        constantFrom([0, 63, 64, 127]),
      ),
    ).map<Step>(
      (fields) => Deliver(
        fields.$1,
        piano,
        fields.$2,
        RawInputMessage(
          kind: fields.$3,
          note: fields.$4.$1,
          velocity: fields.$4.$2,
          sustainValue: fields.$4.$3,
        ),
      ),
    );

bool isMalformed(Deliver step) {
  final channel = step.channel;
  if (channel != null && (channel < 0 || channel > 15)) return true;
  bool outOfRange(int? value) => value == null || value < 0 || value > 127;
  final message = step.message;
  return switch (message.kind) {
    RawInputKind.noteOn || RawInputKind.noteOff =>
      outOfRange(message.note) || outOfRange(message.velocity),
    RawInputKind.sustain => outOfRange(message.sustainValue),
    RawInputKind.allNotesOff || RawInputKind.other => false,
  };
}

/// The sounding state as each channel's key positions, kept independently of
/// the reducer's own bookkeeping.
class KeyboardModel {
  final Map<(int?, int), _Key> _keys = {};
  final Map<int?, bool> _pedals = {};

  void play(int? channel, RawInputMessage message) {
    switch (message.kind) {
      case RawInputKind.noteOn when message.velocity! > 0:
        _keys[(channel, message.note!)] = _Key.held;
      case RawInputKind.noteOn || RawInputKind.noteOff:
        final key = (channel, message.note!);
        if (_keys[key] != _Key.held) return;
        _keys[key] = (_pedals[channel] ?? false) ? _Key.caught : _Key.up;
      case RawInputKind.sustain:
        final down = message.sustainValue! >= 64;
        _pedals[channel] = down;
        if (!down) {
          _keys.updateAll(
            (key, state) =>
                key.$1 == channel && state == _Key.caught ? _Key.up : state,
          );
        }
      case RawInputKind.allNotesOff:
        _keys.clear();
      case RawInputKind.other:
        return;
    }
  }

  InputTemporalSnapshot get snapshot {
    Set<int> notesIn(_Key state) => {
      for (final MapEntry(:key, :value) in _keys.entries)
        if (value == state) key.$2,
    };
    final held = notesIn(_Key.held);
    return InputTemporalSnapshot(
      pressedNoteNumbers: held,
      sustainedNoteNumbers: notesIn(_Key.caught).difference(held),
      pedalDown: _pedals.values.any((down) => down),
    );
  }
}

enum _Key { up, held, caught }

/// [body], with any thrown [Error] reported as a failure.
///
/// kiri_check shrinks only what is thrown as an [Exception], so a crash would
/// otherwise surface unshrunk and without its seed.
void Function(T) failingOnErrors<T>(void Function(T) body) => (value) {
  try {
    body(value);
  } on Error catch (error, stackTrace) {
    fail('$error\n$stackTrace');
  }
};

InputTemporalState replay(Iterable<InputTemporalEvent> events) =>
    events.fold(InputTemporalState.silent, (state, e) => state.applying(e));

/// A locally minimal failing sublist of [steps], found by repeatedly dropping
/// any single step whose removal still fails [check].
///
/// kiri_check shrinks a list only to its prefixes, and a sequence usually
/// fails on its last step, so the prefix it settles on is rarely minimal.
List<Step> minimalFailing(List<Step> steps, void Function(List<Step>) check) {
  bool fails(List<Step> candidate) {
    try {
      check(candidate);
      return false;
    } on Object {
      return true;
    }
  }

  var current = steps;
  for (var i = 0; i < current.length;) {
    final candidate = [...current]..removeAt(i);
    if (fails(candidate)) {
      current = candidate;
      i = 0;
    } else {
      i++;
    }
  }
  return current;
}

/// Checks [check] against generated sequences of [step], reporting a failure's
/// minimal sequence alongside the one kiri_check found.
void forAllSequences(Arbitrary<Step> step, void Function(List<Step>) check) {
  forAll(
    list(step, maxLength: 60),
    seed: seed,
    maxExamples: examples(300),
    failingOnErrors(check),
    onFalsify: (steps) => printOnFailure(
      'Minimal failing steps: ${minimalFailing(steps, check)}',
    ),
  );
}

void checkAnyStream(List<Step> steps) {
  final reducer = InputReducer()..adopt(piano);
  var now = 0;
  var emitted = [...reducer.begin(timestampMs: now)];
  var last = now;

  for (final (index, step) in steps.indexed) {
    final where = 'step $index of $steps';
    // The input clock is monotonic from zero; only a delivery can claim
    // an earlier time than the last one.
    now = max(0, now + step.delta);
    final before = reducer.observation;
    final wasObserving = reducer.isObserving;
    final rejected = reducer.rejectedForeignCount;
    final List<InputTemporalEvent> produced;

    switch (step) {
      case Deliver():
        produced = reducer.receive(step.at(now));
        if (!wasObserving) {
          expect(produced, isEmpty, reason: where);
          expect(reducer.observation, before, reason: where);
        } else if (step.source != reducer.adopted) {
          expect(produced, isEmpty, reason: where);
          expect(reducer.observation, before, reason: where);
          expect(reducer.rejectedForeignCount, rejected + 1);
        } else if (now < last) {
          expect(
            reducer.fault,
            InputIntegrityFault.timestampRegression,
            reason: where,
          );
        } else if (isMalformed(step)) {
          expect(
            reducer.fault,
            InputIntegrityFault.malformedInput,
            reason: where,
          );
        } else {
          expect(reducer.isObserving, isTrue, reason: where);
          last = now;
        }
        if (step.message.kind == RawInputKind.allNotesOff &&
            reducer.isObserving &&
            wasObserving &&
            step.source == reducer.adopted) {
          expect(
            produced.single,
            isA<InputTemporalResetEvent>(),
            reason: where,
          );
        }
      case Fail():
        produced = reducer.fail(
          InputIntegrityFault.observationGap,
          timestampMs: now,
        );
        expect(produced, hasLength(wasObserving ? 1 : 0), reason: where);
        expect(reducer.isObserving, isFalse, reason: where);
      case Begin():
        emitted = [];
        produced = reducer.begin(timestampMs: now);
        last = now;
      case Attach():
        final opening = reducer.opening(timestampMs: now);
        expect(
          replay([opening]),
          reducer.observation,
          reason: 'a late consumer is told what the stream says: $where',
        );
        last = max(last, now);
        produced = const [];
      case Adopt():
        reducer.adopt(step.source);
        produced = const [];
    }

    if (wasObserving && !reducer.isObserving) {
      expect(produced.single, isA<InputTemporalFaultEvent>());
    }
    if (produced.isNotEmpty && step is! Begin) {
      last = max(last, produced.last.timestampMs);
    }
    emitted.addAll(produced);

    expect(replay(emitted), reducer.observation, reason: where);
    for (final (earlier, later) in [
      for (var i = 1; i < emitted.length; i++) (emitted[i - 1], emitted[i]),
    ]) {
      expect(
        later.timestampMs,
        greaterThanOrEqualTo(earlier.timestampMs),
        reason: 'time runs backward within an observation: $where',
      );
    }
    final observed = reducer.observation;
    expect(
      observed.pressedNoteNumbers.intersection(observed.sustainedNoteNumbers),
      isEmpty,
      reason: where,
    );
    if (observed.sustainedNoteNumbers.isNotEmpty) {
      expect(observed.pedalDown, isTrue, reason: where);
    }
  }
}

void checkPerformance(List<Step> steps) {
  final reducer = InputReducer()..adopt(piano);
  reducer.begin(timestampMs: 0);
  final model = KeyboardModel();
  var now = 0;

  for (final (index, step) in steps.indexed) {
    step as Deliver;
    now += step.delta;
    final before = reducer.snapshot;
    final produced = reducer.receive(step.at(now));
    model.play(step.channel, step.message);

    final where = 'step $index of $steps';
    expect(reducer.snapshot, model.snapshot, reason: where);
    expect(reducer.isObserving, isTrue, reason: where);
    if (step.message.kind != RawInputKind.allNotesOff) {
      expect(
        produced.isEmpty,
        reducer.snapshot == before,
        reason: 'an event is emitted exactly when something changed: $where',
      );
    }
  }
}

void main() {
  property(
    'any stream keeps every contract the reducer states',
    () => forAllSequences(anyStep, checkAnyStream),
  );

  property(
    'a well-formed performance sounds as each channel played it',
    () => forAllSequences(anyPlaying, checkPerformance),
  );
}
