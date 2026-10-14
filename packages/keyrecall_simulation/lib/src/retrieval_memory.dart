import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';

/// How a player learns and forgets the notes of each material, as a
/// hypothesis separate from the frozen familiarity model.
///
/// Each material holds a trace: a half-life and the instant it was last
/// encoded. Retrievability halves every half-life since then and decays toward
/// zero, so forgetting can take back what practice gave and what the player
/// came with, and two materials left alone keep their own histories rather than
/// returning to one baseline.
///
/// An attempt encodes the material by what it asked of the player. A
/// successful unguided retrieval lengthens the half-life by [retrievalGain],
/// a started attempt with the notes previewed by [previewGain], one with the
/// notes on the screen throughout by [cuedGain], and supported acquisition
/// work by [acquisitionGain]. A failed unguided retrieval shows the player
/// nothing and encodes nothing. Execution is learned separately, exactly as
/// the frozen model learns it.
///
/// [spacingResponsiveness] is the share of each gain that depends on the time
/// since the material was last encoded, so zero is the control in which massed
/// and spaced encodings teach the same. Encodings [spacingPivot] apart teach
/// the gain at any responsiveness, so the knob moves massed and spaced practice
/// apart without changing what practice at the pivot teaches.
///
/// Uncalibrated: no device observation has measured any of these.
class RetrievalMemory {
  /// Names this model in reports, so runs under it are never read as runs of
  /// the frozen familiarity model.
  static const version = 'retrieval-memory-1';

  /// How long the player's starting familiarity with every material takes to
  /// halve, in days.
  final double initialHalfLifeDays;

  final double retrievalGain;
  final double previewGain;
  final double cuedGain;
  final double acquisitionGain;

  /// In `[0, 1]`. At one, an encoding no time after the last teaches nothing,
  /// one [spacingPivot] after it teaches the gain, and one long after it
  /// approaches twice the gain; at zero, all teach the gain.
  final double spacingResponsiveness;
  final Duration spacingPivot;

  /// The longest a half-life can grow, in days.
  final double ceilingHalfLifeDays;

  const RetrievalMemory({
    required this.initialHalfLifeDays,
    this.retrievalGain = 0.6,
    this.previewGain = 0.3,
    this.cuedGain = 0.1,
    this.acquisitionGain = 0.1,
    this.spacingResponsiveness = 0.5,
    this.spacingPivot = const Duration(days: 1),
    this.ceilingHalfLifeDays = 3650,
  });

  /// What a started or unstarted attempt under [guidance] encodes.
  double gainFor(
    GuidanceContext guidance, {
    required bool started,
    required bool retrieved,
  }) => switch (guidance.independence) {
    2 => retrieved ? retrievalGain : 0,
    1 => started ? previewGain : 0,
    _ => started ? cuedGain : 0,
  };

  /// [trace] encoded again at [at] with [gain].
  MemoryTrace encoded(MemoryTrace trace, DateTime at, double gain) {
    if (gain <= 0) return trace;
    final gap = at.difference(trace.encodedAt).inMicroseconds.toDouble();
    final pivot = spacingPivot.inMicroseconds;
    final spacing =
        1 -
        spacingResponsiveness +
        spacingResponsiveness * 2 * gap / (gap + pivot);
    return MemoryTrace(
      halfLifeDays: math.min(
        ceilingHalfLifeDays,
        trace.halfLifeDays * (1 + gain * spacing),
      ),
      encodedAt: at,
    );
  }

  /// The trace that leaves [familiarity] retrievable at [at] with the initial
  /// half-life.
  MemoryTrace startingTrace(double familiarity, DateTime at) {
    final known = familiarity.clamp(1e-6, 1.0);
    final age = initialHalfLifeDays * -math.log(known) / math.ln2;
    return MemoryTrace(
      halfLifeDays: initialHalfLifeDays,
      encodedAt: at.subtract(
        Duration(microseconds: (age * Duration.microsecondsPerDay).round()),
      ),
    );
  }
}

/// One material's memory: how long it takes to halve and when it was last
/// encoded.
class MemoryTrace {
  final double halfLifeDays;
  final DateTime encodedAt;

  const MemoryTrace({required this.halfLifeDays, required this.encodedAt});

  /// The probability the notes come unaided at [at].
  double retrievabilityAt(DateTime at) {
    final days =
        at.difference(encodedAt).inMicroseconds / Duration.microsecondsPerDay;
    return math.pow(0.5, math.max(0.0, days) / halfLifeDays).toDouble();
  }
}
