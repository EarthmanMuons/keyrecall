import 'package:meta/meta.dart';

import 'canonical_json.dart';

/// How long an attempt's parts took, from when it began listening.
///
/// Durations rather than instants, so they carry nothing about when a person
/// practised, and kept because the transcript they are read from is not: what
/// a gap between attempts, a warm-up, or a slow first note says can only be
/// asked of a history that wrote them down.
@immutable
class AttemptTiming {
  /// From the listening window opening to the attempt closing.
  final int openMs;

  /// From the window opening to the first note, or null when none came.
  final int? firstNoteMs;

  /// From the first note to the last, or null for fewer than two.
  final int? playingMs;

  /// Whether the app lost the foreground while the window was open.
  final bool leftForeground;

  const AttemptTiming({
    required this.openMs,
    this.firstNoteMs,
    this.playingMs,
    this.leftForeground = false,
  });

  @override
  bool operator ==(Object other) =>
      other is AttemptTiming &&
      other.openMs == openMs &&
      other.firstNoteMs == firstNoteMs &&
      other.playingMs == playingMs &&
      other.leftForeground == leftForeground;

  @override
  int get hashCode =>
      Object.hash(openMs, firstNoteMs, playingMs, leftForeground);

  @override
  String toString() =>
      'AttemptTiming(open: ${openMs}ms, first note: $firstNoteMs, '
      'playing: $playingMs, left foreground: $leftForeground)';
}

Map<String, Object?> encodeAttemptTiming(AttemptTiming timing) => {
  'open_ms': timing.openMs,
  'first_note_ms': timing.firstNoteMs,
  'playing_ms': timing.playingMs,
  'left_foreground': timing.leftForeground,
};

AttemptTiming decodeAttemptTiming(
  Map<String, Object?> json, {
  String? location,
}) => AttemptTiming(
  openMs: requireInt(json, 'open_ms', location: location),
  firstNoteMs: asOptionalInt(
    json['first_note_ms'],
    'first_note_ms',
    location: location,
  ),
  playingMs: asOptionalInt(
    json['playing_ms'],
    'playing_ms',
    location: location,
  ),
  leftForeground: requireBool(json, 'left_foreground', location: location),
);
