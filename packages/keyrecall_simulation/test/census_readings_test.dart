import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test(
    'a held-out reading at every session boundary changes no record',
    () async {
      final player = PlayerArchetypes.developing.copyWith(
        familiarityHalfLifeDays: 30,
        retentionHalfLifeDays: 60,
      );
      final sessions = demoSessions(
        from: demoHistoryStart,
        until: demoHistoryStart.add(const Duration(days: 12)),
      );
      final assessment = standardAssessment(
        allPracticeMaterials.take(4).toList(),
        repetitions: 1,
      );
      final readings = <AssessmentReading>[];
      void read(PracticeSession session, PlayerState playing, DateTime at) {
        final belief = session.state.copy();
        const LearnerModel().propagate(belief, at.add(const Duration(days: 7)));
        readings.add(assess(assessment, playing, at: at, state: belief));
      }

      String journal(ServiceCensus census) => (AttemptJournal(
        JournalHeader(profileId: 'census', createdAt: demoHistoryStart),
      )..appendAll(census.records)).toJsonLines();

      final unread = await runServiceCensus(player: player, sessions: sessions);
      final read_ = await runServiceCensus(
        player: player,
        sessions: sessions,
        onArrival: read,
        onClose: read,
      );

      expect(readings, hasLength(2 * sessions.length));
      expect(journal(read_), journal(unread));
    },
  );
}
