import 'package:crisp_notation/crisp_notation.dart' as crisp;
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'fingering.dart';
import 'staff_score.dart';

/// Loads the engraving font's metrics before a staff needs them.
///
/// The first staff to render otherwise waits on an asset read, which is the
/// kind of lag that shows up once, on the first exercise of a session, and
/// then never again while you are looking for it.
Future<void> warmStaffRendering() =>
    crisp.MusicFonts.load(crisp.MusicFont.bravura);

/// Pixels per staff space when nothing can be measured yet, and the range a
/// measured one is held to.
///
/// The floor keeps a wide exercise legible rather than letting it shrink to
/// fit; the ceiling keeps a short one from being blown up to fill a tablet.
const double _fallbackStaffSpace = 7;
const double _minimumStaffSpace = 5;
const double _maximumStaffSpace = 16;

/// The size a note is still comfortably read at, which is what decides how
/// many bars a system is given.
///
/// Above [_minimumStaffSpace], which is where a staff stops being drawn any
/// smaller whatever it costs. This one is where it stops being worth reading,
/// so a system that would fall below it gives up a bar instead.
const double _readableStaffSpace = 9;

/// Staff spaces between the staves of a grand staff, and the wider gap a
/// braced system needs when it is carrying fingering.
///
/// The engraver writes every digit above its note, so the lower staff's sit
/// between the staves and collide with what is written over the upper one.
/// Widening the gap is what this layer can do about that; the fix is a
/// placement the engraver does not yet expose.
const double _standardStaffGap = 4;
const double _fingeredStaffGap = 9;

/// One staff, wrapped into systems and drawn as large as the width allows.
///
/// The size is chosen here and the line breaking is left to the engraver. A
/// renderer packing measures to a width needs a size chosen in advance, which
/// on a phone is a small staff with space left over; picking the size first
/// and handing it over means the systems are as large as they can be and are
/// still broken, restated and justified the way an engraver would.
class FittedStaff extends StatelessWidget {
  const FittedStaff({
    required this.score,
    required this.theme,
    this.sizing,
    this.elementColors = const {},
    this.showsNoteNames = false,
    super.key,
  });

  final crisp.Score score;

  /// The score the staff is sized against, when it is not the one being drawn.
  ///
  /// What a staff that fills in over an attempt is measured by: the size comes
  /// from everything it will hold, so nothing already on it moves or changes
  /// size when the next note arrives.
  final crisp.Score? sizing;

  final crisp.CrispNotationTheme theme;

  /// What to draw particular elements in, by id.
  final Map<String, Color> elementColors;

  final bool showsNoteNames;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured against everything the staff will hold, so the system it
        // settles on is the one the whole exercise reads at rather than the
        // one whatever is on screen so far happens to allow.
        final whole = sizing ?? score;
        final bars = barsPerSystem(
          whole,
          width: constraints.maxWidth,
          minimumStaffSpace: _readableStaffSpace,
        );
        final space = _spaceFor(
          fittedStaffSpace(
            rowsOf(whole, measuresPerRow: bars),
            width: constraints.maxWidth,
          ),
        );
        return crisp.MultiSystemView(
          score: score,
          theme: theme,
          staffSpace: space,
          elementColors: elementColors,
          showNoteNames: showsNoteNames,
        );
      },
    );
  }
}

/// A braced grand staff, wrapped into systems and drawn as large as the width
/// allows.
///
/// [FittedStaff] for two staves, and for the same reason: the size is chosen
/// here and the line breaking is left to the engraver, which is what restates
/// the clefs on a new system, writes the time signature once, and keeps the
/// barlines of the two staves together.
///
/// Drawn by the interactive view, which is the braced one that takes element
/// colors and packs systems to a width. Nothing is wired to it, so it stays a
/// rendering.
class FittedGrandStaff extends StatelessWidget {
  const FittedGrandStaff({
    required this.grandStaff,
    required this.theme,
    this.sizing,
    this.staffGap = _standardStaffGap,
    this.elementColors = const {},
    super.key,
  });

  final crisp.GrandStaff grandStaff;

  /// Everything the staff will hold, when that is more than it is drawing.
  final crisp.GrandStaff? sizing;

  final crisp.CrispNotationTheme theme;

  /// Staff spaces between the two staves.
  final double staffGap;

  /// What to draw particular elements in, by id.
  final Map<String, Color> elementColors;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final whole = sizing ?? grandStaff;
      final space = _spaceFor(
        fittedGrandStaffSpace(
          rowsOfGrandStaff(
            whole,
            measuresPerRow: barsPerBracedSystem(
              whole,
              width: constraints.maxWidth,
              minimumStaffSpace: _readableStaffSpace,
            ),
          ),
          width: constraints.maxWidth,
        ),
      );
      return crisp.InteractiveGrandStaffView(
        grandStaff: grandStaff,
        theme: theme,
        staffSpace: space,
        staffGap: staffGap,
        elementColors: elementColors,
      );
    },
  );
}

double _spaceFor(double? fitted) => (fitted ?? _fallbackStaffSpace).clamp(
  _minimumStaffSpace,
  _maximumStaffSpace,
);

/// The theme a staff is drawn in, taken from the app's colours.
crisp.CrispNotationTheme staffTheme(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return crisp.CrispNotationTheme.standard.copyWith(
    staffColor: scheme.onSurfaceVariant,
    noteColor: scheme.onSurface,
    highlightColor: scheme.primary,
  );
}

/// The exercise's notes, written out.
///
/// A cue surface, not a progress display: it draws what the exercise asks for
/// and knows nothing about what has been played. Showing where the learner is,
/// or filling notes in as they arrive, needs a layer that relates a
/// performance to the realization, and that layer does not exist.
///
/// Both hands get a braced grand staff, one hand a single staff in its own
/// clef.
class StaffCue extends StatelessWidget {
  const StaffCue({
    required this.exercise,
    this.showsFingering = false,
    super.key,
  });

  /// The exercise whose realization is drawn.
  final Exercise exercise;

  /// Whether the fingering is written over the notes.
  ///
  /// The motor cue is its own channel, so the staff carries it only when that
  /// channel is open rather than whenever the catalog happens to have one.
  final bool showsFingering;

  @override
  Widget build(BuildContext context) {
    final realization = realize(exercise);
    final theme = staffTheme(context);

    // The cue is showing the scale on purpose, so it is written the way a
    // scale book writes it. The staff that grows from what was played is not;
    // see [TranscriptStaff].
    final keySignature = crisp.KeySignature(
      keySignatureFifths(exercise.material),
    );

    if (realization.hands.length > 1) {
      return FittedGrandStaff(
        staffGap: showsFingering ? _fingeredStaffGap : _standardStaffGap,
        grandStaff: grandStaffFor(
          realization,
          fingering: {
            if (showsFingering)
              for (final hand in realization.hands)
                hand: displayFingeringFor(exercise, hand),
          },
          keySignature: keySignature,
        ),
        theme: theme,
      );
    }
    return FittedStaff(
      score: staffScoreFor(
        realization,
        realization.hands.single,
        fingering: showsFingering
            ? displayFingeringFor(exercise, realization.hands.single)
            : null,
        keySignature: keySignature,
      ),
      theme: theme,
    );
  }
}

/// What the learner has played so far, written out.
///
/// The same surface as [StaffCue] carrying different information: this one is
/// written from observations and starts with nothing on it, so it discloses
/// nothing about what is coming. Its width is held from the first frame, which
/// says how much is being asked for and not what any of it is.
///
/// One staff for one hand, a braced pair for two. Which hand played a note is
/// not something the input stream says, so a note on the grand staff is placed
/// by its register, which is what a clef reports anyway.
class TranscriptStaff extends StatelessWidget {
  const TranscriptStaff({
    required this.transcript,
    required this.exercise,
    super.key,
  });

  /// What has been played.
  final PerformanceTranscript transcript;

  /// The exercise being attempted, which decides the clef.
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final realization = realize(exercise);
    if (realization.hands.length > 1) {
      final whole = transcriptGrandStaffFor(
        transcript,
        splitMidiNote: registerSplitFor(realization),
        reserve: realization.noteCount,
      );
      return FittedGrandStaff(
        grandStaff: barsOfGrandStaff(whole, barsReachedBy(transcript.length)),
        sizing: whole,
        theme: staffTheme(context),
        // The slots are there to hold the space. Drawing them would say the
        // learner rested, which is a claim about a performance nobody has
        // made.
        elementColors: {
          for (final id in reservedGrandStaffIds(whole)) id: Colors.transparent,
        },
      );
    }

    final score = transcriptScoreFor(
      transcript,
      clef: exercise.conditions.hands == HandConfiguration.left
          ? crisp.Clef.bass
          : crisp.Clef.treble,
      // Room for what was asked for, held from the first frame. A staff that
      // grew a note at a time would move every note already on it each time
      // one arrived, which is the one thing a learner watching it cannot be
      // reading past.
      reserve: realization.moments.length,
    );

    return FittedStaff(
      // Drawn as far as the performance has reached, sized by all of it.
      score: barsOf(score, barsReachedBy(transcript.length)),
      sizing: score,
      theme: staffTheme(context),
      // The slots are there to hold the space. Drawing them would say the
      // learner rested, which is a claim about a performance nobody has made.
      elementColors: {
        for (final id in reservedIds(score)) id: Colors.transparent,
      },
    );
  }
}
