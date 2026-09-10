import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// Supported acquisition of arpeggios, through the ordinary sitting.
///
/// The rule is family-neutral and the scale tests prove the rule. What these
/// ask is whether the arpeggio family's own declaration reaches it: the floor
/// it names, the task it names below that floor, and what a sitting does with
/// the pair.
void main() {
  final arpeggio = proofArpeggios.first;

  /// A beginner working one arpeggio and managing none of it.
  Future<PracticeSession> struggling(PracticeStore store) => openSession(
    store,
    materials: [arpeggio],
    placement: PlacementTier.beginner,
  );

  /// An attempt that started and taught the model something without
  /// demonstrating a tempo, which is the state the floor check reads.
  Outcome managedNothing() => outcomeOf(
    retrieval: FactualRetrieval.notTested,
    quality: 0.1,
    tempoRatio: 0.3,
  );

  /// The notes [task] asks for, in order.
  List<int> notesOf(AcquisitionTask task) => [
    for (final moment in realizeAcquisition(task).moments)
      moment.noteFor(Hand.right)!.midiNote,
  ];

  PerformanceTranscript playing(
    AcquisitionTask task,
    List<int> midiNotes, {
    int gapMs = 900,
  }) {
    var transcript = PerformanceTranscript.empty;
    for (final (index, midiNote) in midiNotes.indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: task.material),
        timestampMs: index * gapMs,
      );
    }
    return transcript;
  }

  /// Runs a sitting, playing [play] at every supported task it offers.
  Future<List<Object>> sitting(
    PracticeSession session, {
    int slots = 14,
    PerformanceTranscript Function(AcquisitionTask task)? play,
  }) async {
    final offered = <Object>[];
    for (var slot = 0; slot < slots; slot++) {
      final at = t0.plusDays(0.5 * (slot + 1));
      final decision = await session.decideOutcome(at: at);
      if (decision is PresentedAcquisition) {
        offered.add(decision.task);
        await session.closeAcquisition(
          play?.call(decision.task) ?? PerformanceTranscript.empty,
          at: at,
        );
        continue;
      }
      if (decision is! PresentedAttempt) break;
      offered.add(decision.exercise);
      await session.acknowledgePresentation(decision.decision.attemptId);
      await session.closeWithOutcome(managedNothing(), observedWallTime: at);
    }
    return offered;
  }

  test('the declared floor is asked before its supported version', () async {
    // The distinction the family-neutral sequence rests on. Failing an ordinary
    // rung is a reason to ask for the floor; only failing the floor is a reason
    // to take the tempo off it.
    final offered = await sitting(
      await struggling(InMemoryPracticeStore(createdAt: t0)),
    );
    final firstTask = offered.indexWhere((entry) => entry is AcquisitionTask);

    expect(firstTask, greaterThan(-1), reason: 'supported work never arrived');
    final task = offered[firstTask] as AcquisitionTask;
    expect(
      offered.take(firstTask),
      contains(task.parent),
      reason: 'the floor was relaxed before it was ever asked for',
    );
  });

  test('the supported task is the arpeggio floor, unmetered', () async {
    final offered = await sitting(
      await struggling(InMemoryPracticeStore(createdAt: t0)),
    );
    final task =
        offered.whereType<AcquisitionTask>().firstOrNull ??
        (throw StateError('supported work never arrived'));

    expect(task.material, arpeggio);
    expect(task.timing, TimingDemand.unmetered);
    expect(task.advancement, TaskAdvancement.learnerDriven);
    // Two traversals of the one-octave triad, which is what the continuity
    // criterion needs and not a dose anyone chose: three intervals a traversal
    // and five wanted.
    expect(task.portion, const TraversalRepetitions(2));
    expect(notesOf(task), hasLength(8));
    // The family's own floor: right hand, one octave, ascending, cued.
    expect(task.parent.conditions.hands, HandConfiguration.right);
    expect(task.parent.conditions.octaves, 1);
    expect(task.parent.conditions.direction, ExerciseDirection.up);
    expect(task.parent.guidance, GuidanceContext.continuouslyCued);
  });

  test('the three outcomes are told apart', () async {
    final session = await struggling(InMemoryPracticeStore(createdAt: t0));
    var attempt = 0;

    await sitting(
      session,
      slots: 20,
      play: (task) {
        final notes = notesOf(task);
        return switch (attempt++) {
          // Everything, right the first time.
          0 => playing(task, notes),
          // Everything, reached through an extra note.
          1 => playing(task, [notes.first, ...notes]),
          // Stopped inside it.
          _ => playing(task, notes.take(2).toList()),
        };
      },
    );
    final records = session.acquisitionJournal.attempts;

    expect(records, hasLength(greaterThanOrEqualTo(3)));
    expect(records[0].completion, AcquisitionCompletion.completedCleanly);
    expect(
      records[1].completion,
      AcquisitionCompletion.completedWithCorrections,
    );
    expect(records[2].completion, AcquisitionCompletion.notCompleted);
    expect(records[2].firstAbsentPosition, isNotNull);
  });

  test('two clean traversals earn a probe of the unchanged parent', () async {
    // What the repetitions are for. One traversal of a triad supplies three
    // intervals, and the criterion wants five, so a single clean ascent could
    // never say the motion was fluent however well it went.
    final session = await struggling(InMemoryPracticeStore(createdAt: t0));

    final offered = await sitting(
      session,
      slots: 20,
      play: (task) => playing(task, notesOf(task)),
    );
    final earned = session.acquisitionJournal.attempts.first;

    expect(earned.completion, AcquisitionCompletion.completedCleanly);
    expect(earned.earnedProbe, isTrue);
    // Six intervals rather than seven: the reset between the two traversals is
    // the one the task asked for and is not read as playing.
    expect(earned.gaps, hasLength(6));
    expect(
      earned.gaps.map((gap) => gap.fromPosition),
      isNot(contains(3)),
      reason: 'the reset between traversals was read as a wait inside one',
    );

    // The probe is the parent as it stands, tempo and all, and it comes after
    // the supported work rather than instead of it.
    final task = offered.whereType<AcquisitionTask>().first;
    expect(
      offered.skip(offered.indexOf(task) + 1).whereType<Exercise>(),
      contains(task.parent),
    );
  });

  test('the reset between traversals is allowed to be long', () async {
    // Taking a moment to put the hand back is what the task asked for. Reading
    // it as a stall would make the scaffold that supplies the evidence the
    // reason the evidence fails.
    final session = await struggling(InMemoryPracticeStore(createdAt: t0));

    await sitting(
      session,
      slots: 20,
      play: (task) {
        final notes = notesOf(task);
        var transcript = PerformanceTranscript.empty;
        var at = 0;
        for (final (index, midiNote) in notes.indexed) {
          if (index > 0) at += index == notes.length ~/ 2 ? 6000 : 900;
          transcript = transcript.appending(
            pitch: spellObservedPitch(midiNote, material: task.material),
            timestampMs: at,
          );
        }
        return transcript;
      },
    );
    final record = session.acquisitionJournal.attempts.first;

    expect(record.completion, AcquisitionCompletion.completedCleanly);
    expect(record.earnedProbe, isTrue);
  });

  test('supported work is a step aside, not the sitting', () async {
    // The set-aside and the dose, read off one sitting: a stuck floor that goes
    // on being stuck does not fill the slots with its own relaxed version.
    final offered = await sitting(
      await struggling(InMemoryPracticeStore(createdAt: t0)),
      slots: 14,
    );
    final tasks = offered.whereType<AcquisitionTask>();

    expect(tasks, isNotEmpty);
    expect(tasks.length * 2, lessThan(offered.length));
    for (var i = 1; i < offered.length; i++) {
      if (offered[i] is! AcquisitionTask) continue;
      expect(
        offered[i - 1],
        isNot(isA<AcquisitionTask>()),
        reason: 'supported work landed on consecutive opportunities',
      );
    }
  });
}
