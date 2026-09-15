import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  /// What a supported task resolves to: everything the parent supplies, and
  /// no pulse, because the task is what removed the tempo.
  PresentationRecord presented() => PresentationRecord(
    policyVersion: 'v1-presentation-0',
    conditions: PresentationConditions(
      pitchCue: PitchCue.full,
      cueModality: CueModality.keyboardAndStaff,
      motorCue: MotorCue.fingering,
      performanceFeedback: PerformanceFeedback.neutralEcho,
      tempoSupport: TempoSupport.none,
      locatorFeedback: LocatorFeedback.positionTracking,
    ),
    delivery: PresentationDelivery(tempo: TempoDelivery.notRequested()),
  );

  test('a supported attempt keeps what it was presented under', () async {
    final directory = await Directory.systemTemp.createTemp(
      'acquisition-presentation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final disk = FilePracticeStore(directory);
    final session = await openSession(
      disk,
      pipeline: const AlwaysOffersAcquisition(),
    );

    expect(
      await session.decideOutcome(at: t0.plusDays(1)),
      isA<PresentedAcquisition>(),
    );
    final closed = await session.closeAcquisition(
      PerformanceTranscript.empty,
      at: t0.plusDays(1),
      presentation: presented(),
    );

    expect(closed.presentation, presented());

    // Reopened from the file rather than read back out of memory: what the
    // record claims and what the history holds have to be the same thing.
    final reopened = await openSession(disk, sessionId: 'reopened');
    final stored = reopened.acquisitionJournal.attempts.last;

    expect(stored.presentation, presented());
    expect(
      stored.presentation!.conditions.tempoSupport,
      TempoSupport.none,
      reason:
          'the task removed the tempo, and a record saying a count-in was '
          'supplied would describe support this attempt never had',
    );
    expect(stored.presentation!.delivery.tempo.requestedBeats, 0);
  });
}
