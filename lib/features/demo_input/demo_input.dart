/// A synthetic instrument, so the practice loop runs with nothing plugged in.
///
/// It plays what it is told and produces the same normalized event stream a
/// real keyboard does. Nothing downstream can tell which one it is talking to,
/// which is the whole point: the scheduler, the learner model, and the attempt
/// journal can all be exercised end to end before any hardware exists.
///
/// ## What is deliberately not here
///
/// The instrument knows nothing about scales, exercises, or whether what it
/// played was correct. Deciding those is the practice loop's job, and an
/// instrument that knew them would be simulating the answer rather than the
/// playing.
///
/// There is also no authored sequence. WhatChord's version drives a scripted
/// tour that sets theme, key, and prompts alongside the notes, which is how it
/// produces deterministic marketing screenshots. KeyRecall will want that too.
/// It belongs in a layer *above* this one, telling the instrument what to play
/// while separately setting whatever app state a shot needs; this stays a
/// device that plays notes. That split is why adding it later will not disturb
/// anything here.
library;

export 'cancelable_timer_sequence.dart';
export 'demo_input_notifier.dart';
export 'demo_temporal_events_provider.dart';
