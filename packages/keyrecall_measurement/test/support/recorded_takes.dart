import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';

/// The takes recorded in `analysis/onset-grouping/`, and what was played.
///
/// Read as exported, so arrival order and arrivals sharing a millisecond reach
/// a test the way they reach the app.
const Map<String, (String, ScaleForm)> recordedTakes = {
  'comfortable-c-major': ('C', ScaleForm.major),
  'fast-c-major-with-stumble': ('C', ScaleForm.major),
  'uneven-d-major': ('D', ScaleForm.major),
  'deliberate-rolled-c-major': ('C', ScaleForm.major),
  'hands-out-of-phase-c-major': ('C', ScaleForm.major),
};

/// The material [take] was played in.
TechnicalMaterial materialOf(String take) {
  final (tonic, form) = recordedTakes[take]!;
  return TechnicalMaterial(tonic, form);
}

/// One octave of [take]'s scale, hands together, up and back down.
ExerciseRealization realizationOf(String take) => realize(
  Exercise.linear(
    material: materialOf(take),
    hands: HandConfiguration.together,
    octaves: 1,
  ),
);

/// What was played in [take].
PerformanceTranscript transcriptOf(String take) {
  final file = File('../../analysis/onset-grouping/takes/$take.json');
  final recorded =
      (jsonDecode(file.readAsStringSync()) as Map<String, Object?>)['notes']!
          as List<Object?>;
  final material = materialOf(take);

  var transcript = PerformanceTranscript.empty;
  for (final note in recorded.cast<Map<String, Object?>>()) {
    transcript = transcript.appending(
      pitch: spellObservedPitch(note['note']! as int, material: material),
      timestampMs: note['ms']! as int,
    );
  }
  return transcript;
}
