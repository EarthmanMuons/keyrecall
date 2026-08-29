/// The tempi a mechanical metronome offers, and the steps between them.
///
/// Maelzel's progression: two apart to 60, three to 72, four to 120, six to
/// 144, eight to 208. Its origin is the escapement of a clockwork device
/// rather than anything about learning, so nothing here treats these numbers
/// as pedagogically privileged. What they are is a quantization grid a
/// musician already reads, with steps that grow as the tempo does, which is
/// the right shape for the thing they are being used for: a fixed number of
/// beats per minute does not mean a fixed amount at both ends of the range.
///
/// KeyRecall uses it as an **adjacency relation** rather than a candidate set.
/// Generating all thirty-nine would multiply the candidate space by ten to
/// express a question that is always local — is the next rung up useful work
/// yet — and answering that needs two neighbours, not a catalog.
const List<double> metronomeLadder = [
  40, 42, 44, 46, 48, 50, 52, 54, 56, 58, //
  60, 63, 66, 69, //
  72, 76, 80, 84, 88, 92, 96, 100, 104, 108, 112, 116, 120, //
  126, 132, 138, 144, //
  152, 160, 168, 176, 184, 192, 200, 208,
];

/// Which rung [bpm] is, rounding to the nearest when it falls between two.
///
/// Ties round down, so a tempo exactly between two rungs is read as the
/// slower one and stepping up from it lands on the faster.
int tempoRungOf(double bpm) {
  var nearest = 0;
  for (var rung = 1; rung < metronomeLadder.length; rung++) {
    if ((metronomeLadder[rung] - bpm).abs() <
        (metronomeLadder[nearest] - bpm).abs()) {
      nearest = rung;
    }
  }
  return nearest;
}

/// The tempo [steps] rungs from [bpm], stopping at the ends of the ladder.
///
/// Clamped rather than absent at the ends, because there is always a tempo to
/// ask for: the slowest is still a tempo, and a learner at the top of the
/// ladder is asked for it again rather than for nothing.
double tempoStepped(double bpm, int steps) =>
    metronomeLadder[(tempoRungOf(bpm) + steps).clamp(
      0,
      metronomeLadder.length - 1,
    )];

/// The next rung up from [bpm].
double tempoAfter(double bpm) => tempoStepped(bpm, 1);

/// The next rung down from [bpm].
double tempoBefore(double bpm) => tempoStepped(bpm, -1);

/// Whether there is a rung above [bpm].
bool hasTempoAfter(double bpm) => tempoRungOf(bpm) < metronomeLadder.length - 1;

/// Whether there is a rung below [bpm].
bool hasTempoBefore(double bpm) => tempoRungOf(bpm) > 0;

/// Whether [bpm] is a rung rather than a value between two.
bool isTempoRung(double bpm) => metronomeLadder.contains(bpm);
