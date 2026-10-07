import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:keyrecall_testing/keyrecall_testing.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:kiri_check/stateful_test.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// A write a session makes that storage can be made to fail.
enum Boundary {
  savePending,
  appendAttempt,
  clearPending,
  appendAcquisition,
  saveCheckpoint,
}

class InjectedFailure implements Exception {
  const InjectedFailure();

  @override
  String toString() => 'InjectedFailure';
}

/// Memory storage whose next write at an armed [Boundary] fails, either
/// before anything is written or after the write has landed.
class FaultyStore extends InMemoryPracticeStore {
  FaultyStore() : super(createdAt: t0);

  ({Boundary boundary, bool afterWriting})? armed;

  /// While set, writes are dropped and nothing armed fires, so a session can
  /// be opened to look at what is durable without changing it.
  bool readOnly = false;

  final List<String> fired = [];

  Future<void> _write(Boundary boundary, Future<void> Function() write) async {
    if (readOnly) return;
    final fault = armed;
    if (fault == null || fault.boundary != boundary) return write();
    armed = null;
    fired.add('${boundary.name}${fault.afterWriting ? ' after writing' : ''}');
    if (fault.afterWriting) await write();
    throw const InjectedFailure();
  }

  @override
  Future<void> savePendingDecision(PendingDecision decision) =>
      _write(Boundary.savePending, () => super.savePendingDecision(decision));

  @override
  Future<void> appendAttempt(AttemptRecord record) =>
      _write(Boundary.appendAttempt, () => super.appendAttempt(record));

  @override
  Future<void> clearPendingDecision(String profileId) => _write(
    Boundary.clearPending,
    () => super.clearPendingDecision(profileId),
  );

  @override
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry) => _write(
    Boundary.appendAcquisition,
    () => super.appendAcquisitionEntry(entry),
  );

  @override
  Future<void> saveCheckpoint(LearnerStateCheckpoint checkpoint) =>
      _write(Boundary.saveCheckpoint, () => super.saveCheckpoint(checkpoint));

  @override
  Future<void> appendSelectionDiagnostics(
    String profileId,
    String attemptId,
    String diagnostics,
  ) async {
    if (readOnly) return;
    await super.appendSelectionDiagnostics(profileId, attemptId, diagnostics);
  }
}

/// The production pipeline, offering supported work whenever [offering] is
/// set, so a sequence decides when acquisition is on screen.
class OffersOnRequest extends SchedulerPipeline {
  OffersOnRequest() : super(learner: learner);

  bool offering = false;

  @override
  ({
    SelectionResult result,
    bool guidanceProbeAvailable,
    bool guidanceProbeSelected,
  })
  evaluateSlot({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    AttemptHistory? history,
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
    UncoveredTargets uncoveredTargets = UncoveredTargets.none,
    bool diagnose = true,
  }) =>
      (offering
              ? const AlwaysOffersAcquisition()
              : SchedulerPipeline(learner: learner))
          .evaluateSlot(
            state: state,
            session: session,
            candidates: candidates,
            at: at,
            overrides: overrides,
            acquisitionFloor: acquisitionFloor,
            acquisitionFamilyFloor: acquisitionFamilyFloor,
            acquisition: acquisition,
            history: history,
            practiceEntryPolicy: practiceEntryPolicy,
            emphasis: emphasis,
            uncoveredTargets: uncoveredTargets,
            diagnose: diagnose,
          );
}

final Profile bob = Profile(
  id: '3f2a6c18-0000-4000-8000-000000000b0b',
  displayName: 'Bob',
  createdAt: t0,
  placement: PlacementTier.beginner,
);

/// What one profile has been asked and has answered, by the device's account.
class Ledger {
  final Profile profile;

  /// Never restarts, so a relaunch cannot reuse an attempt id.
  final IdGenerator nextId;

  final Set<String> sessions = {};
  final Set<String> decided = {};
  final Set<String> offered = {};

  /// Closes that returned, and closes that threw, which may have landed.
  final Set<String> accepted = {};
  final Set<String> uncertain = {};
  final Set<String> acquired = {};
  final Set<String> acquisitionUncertain = {};

  /// The ordinary attempt on screen or pending, until it is closed or
  /// abandoned. Survives a relaunch.
  ({String id, Exercise exercise})? shown;

  /// The supported task on screen, which a relaunch drops.
  String? acquisitionShown;

  /// Whether a pending slot may hold a decision whose save was reported as
  /// failed, and so was never shown.
  bool unshownPending = false;

  /// Whether an abandon reported failing may still have cleared the pending
  /// slot.
  bool abandonMayHaveLanded = false;

  Ledger(this.profile) : nextId = countingIds(profile.displayName);
}

/// How an ordinary attempt ends: played, declined where the rung tests
/// retrieval and otherwise unmeasured, or unmeasured.
enum Closing { played, declined, unmeasured }

/// One install: a store, two profiles, and the session in front of one.
class Device {
  final FaultyStore store = FaultyStore();
  final OffersOnRequest pipeline = OffersOnRequest();
  final Map<String, Ledger> ledgers = {
    for (final profile in [alice, bob]) profile.id: Ledger(profile),
  };
  late Ledger current = ledgers[alice.id]!;
  PracticeSession? session;
  DateTime now = t0.plusDays(1);
  int sessionsOpened = 0;

  /// Whether the last close threw, so the next one finishes its transaction
  /// rather than starting one.
  bool commitUnsettled = false;
  bool acquisitionUnsettled = false;

  final Reached<String> reached;

  Device(this.reached);

  Future<PracticeSession> _open(Ledger ledger, {required String sessionId}) =>
      PracticeSession.open(
        store: store,
        profile: ledger.profile,
        materials: fixtureMaterials,
        learner: learner,
        pipeline: pipeline,
        sessionId: sessionId,
        nextId: ledger.nextId,
      );

  Future<void> open(Ledger ledger) async {
    session = null;
    current = ledger;
    commitUnsettled = false;
    acquisitionUnsettled = false;
    ledger.acquisitionShown = null;
    final sessionId = 'session-${sessionsOpened++}';
    ledger.sessions.add(sessionId);
    final PracticeSession opened;
    try {
      opened = await _open(ledger, sessionId: sessionId);
    } on InjectedFailure {
      reached.add('open interrupted');
      return;
    }
    session = opened;
    _adoptPending(ledger, opened.pending);
  }

  /// Settles the ledger against the pending decision an open recovered.
  void _adoptPending(Ledger ledger, PendingDecision? pending) {
    final shown = ledger.shown;
    if (pending != null && shown == null) {
      expect(
        ledger.unshownPending,
        isTrue,
        reason: 'recovered ${pending.attemptId}, which nothing showed',
      );
      reached.add('recovered an unshown decision');
      ledger.decided.add(pending.attemptId);
      ledger.shown = (id: pending.attemptId, exercise: pending.exercise);
    } else if (pending != null) {
      expect(pending.attemptId, shown!.id);
      reached.add('resumed a pending attempt');
    } else if (shown != null && ledger.abandonMayHaveLanded) {
      reached.add('a relaunch found an uncertain abandon cleared');
      ledger.shown = null;
    } else if (shown != null) {
      expect(
        ledger.uncertain,
        contains(shown.id),
        reason: '${shown.id} was shown and is neither pending nor closed',
      );
      reached.add('a relaunch found an uncertain close durable');
      ledger.shown = null;
    }
    ledger
      ..unshownPending = false
      ..abandonMayHaveLanded = false;
  }

  Future<PracticeSession?> _ready() async {
    if (session == null) await open(current);
    return session;
  }

  Future<void> decide(int minutes, bool offering) async {
    final session = await _ready();
    if (session == null) return;
    final ledger = current;
    now = now.add(Duration(minutes: minutes));
    pipeline.offering = offering;
    if (ledger.shown != null || ledger.acquisitionShown != null) {
      expect(session.hasOutstandingAttempt || session.pending != null, isTrue);
      await _refused(
        () => session.decideOutcome(at: now),
        'deciding again would abandon what was shown',
      );
      return;
    }
    final before = learnerStateHash(session.state);
    final PracticeDecision decision;
    try {
      decision = await session.decideOutcome(at: now);
    } on InjectedFailure {
      reached.add('decision not saved');
      ledger.unshownPending = true;
      expect(session.hasOutstandingAttempt, isFalse);
      expect(learnerStateHash(session.state), before);
      return;
    }
    switch (decision) {
      case PresentedAttempt(:final decision, :final exercise):
        ledger.decided.add(decision.attemptId);
        ledger.shown = (id: decision.attemptId, exercise: exercise);
        ledger.unshownPending = false;
        reached.add('presented');
      case PresentedAcquisition(:final attemptId):
        ledger.offered.add(attemptId);
        ledger.acquisitionShown = attemptId;
        reached.add('offered acquisition');
      default:
        reached.add('nothing presented');
    }
  }

  Future<void> acknowledge() async {
    final session = await _ready();
    final shown = current.shown;
    if (session == null || shown == null) return;
    await session.acknowledgePresentation(shown.id);
  }

  Future<void> close(Closing how) async {
    final session = await _ready();
    if (session == null) return;
    final ledger = current;
    final shown = ledger.shown;
    if (shown == null) {
      if (!session.hasOutstandingAttempt) {
        await _refused(
          () => session.closeUnmeasured(
            termination: AttemptTermination.inputInterrupted,
          ),
          'nothing is outstanding to close',
        );
      }
      return;
    }
    final before = learnerStateHash(session.state);
    final length = session.journal.length;
    final retrying = commitUnsettled;
    final AttemptRecord record;
    try {
      record = await switch (how) {
        Closing.played => session.closeWithOutcome(
          outcomeFor(shown.exercise, succeeded: now.minute.isEven),
        ),
        Closing.declined
            when retrying || shown.exercise.guidance.isRetrievalObserved =>
          session.closeDeclined(transcript: PerformanceTranscript.empty),
        Closing.declined || Closing.unmeasured => session.closeUnmeasured(
          termination: AttemptTermination.inputInterrupted,
        ),
      };
    } on InjectedFailure {
      ledger.uncertain.add(shown.id);
      commitUnsettled = true;
      if ((await store.loadJournal(ledger.profile.id)).contains(shown.id)) {
        reached.add('a close failed after its attempt became history');
        expect(
          session.journal.contains(shown.id),
          isTrue,
          reason: 'an attempt in history is in the session that wrote it',
        );
      } else {
        expect(
          learnerStateHash(session.state),
          before,
          reason: 'a close that wrote nothing moved the session',
        );
        expect(session.journal.length, length);
      }
      return;
    }
    if (retrying) reached.add('a retried close finished');
    expect(record.identity.attemptId, shown.id);
    final durable = await store.loadJournal(ledger.profile.id);
    expect(
      durable.records
          .where((held) => held.identity.attemptId == shown.id)
          .map((held) => contentHash(held.toJson())),
      [contentHash(record.toJson())],
      reason: 'what a close returns is what is durable, once',
    );
    ledger
      ..accepted.add(shown.id)
      ..shown = null;
    commitUnsettled = false;
    reached.add('closed ${how.name}');
  }

  Future<void> closeAcquisition() async {
    final session = await _ready();
    if (session == null) return;
    final ledger = current;
    final offered = ledger.acquisitionShown;
    if (offered == null) {
      if (!session.hasOutstandingAttempt) {
        await _refused(
          () => session.closeAcquisition(PerformanceTranscript.empty, at: now),
          'no supported task is outstanding',
        );
      }
      return;
    }
    final retrying = acquisitionUnsettled;
    try {
      final record = await session.closeAcquisition(
        PerformanceTranscript.empty,
        at: now,
      );
      expect(record.identity.attemptId, offered);
    } on InjectedFailure {
      ledger.acquisitionUncertain.add(offered);
      acquisitionUnsettled = true;
      return;
    }
    if (retrying) reached.add('a retried acquisition close finished');
    ledger
      ..acquired.add(offered)
      ..acquisitionShown = null;
    acquisitionUnsettled = false;
    reached.add('closed acquisition');
  }

  Future<void> abandon() async {
    final session = await _ready();
    if (session == null) return;
    final ledger = current;
    final shown = ledger.shown;
    if (shown == null && ledger.acquisitionShown == null) return;
    final durable = await store.loadJournal(ledger.profile.id);
    if (shown != null && durable.contains(shown.id)) {
      await _refused(
        session.abandonPending,
        'an attempt that is already history cannot be abandoned',
      );
      reached.add('refused to abandon history');
      return;
    }
    try {
      await session.abandonPending();
    } on InjectedFailure {
      reached.add('abandon not saved');
      ledger.abandonMayHaveLanded = true;
      return;
    }
    ledger
      ..shown = null
      ..acquisitionShown = null
      ..abandonMayHaveLanded = false;
    commitUnsettled = false;
    acquisitionUnsettled = false;
    reached.add('abandoned');
  }

  Future<void> checkpoint() async {
    final session = await _ready();
    if (session == null) return;
    try {
      if (await session.saveCheckpoint() != null) reached.add('checkpointed');
    } on InjectedFailure {
      reached.add('checkpoint not saved');
    }
  }

  void arm(Boundary boundary, bool afterWriting) =>
      store.armed = (boundary: boundary, afterWriting: afterWriting);

  Future<void> relaunch() => open(current);

  Future<void> switchProfile() =>
      open(ledgers.values.firstWhere((ledger) => ledger != current));

  /// Checks what is durable against the ledgers, and the live session against
  /// a fresh reading of it.
  Future<void> check() async {
    for (final ledger in ledgers.values) {
      if (ledger.sessions.isEmpty) continue;
      final id = ledger.profile.id;
      final journal = await store.loadJournal(id);
      final attempts = [
        for (final record in journal.records) record.identity.attemptId,
      ];
      expect(attempts.toSet(), hasLength(attempts.length));
      for (final record in journal.records) {
        expect(record.identity.profileId, id);
        expect(ledger.sessions, contains(record.identity.sessionId));
      }
      expect(ledger.decided, containsAll(attempts));
      expect(attempts, containsAll(ledger.accepted));
      expect(
        {...ledger.accepted, ...ledger.uncertain},
        containsAll(attempts),
        reason: 'only a close puts an attempt in history',
      );

      final log = await store.loadAcquisitionJournal(id);
      for (final entry in log.records) {
        expect(entry.identity.profileId, id);
        expect(ledger.sessions, contains(entry.identity.sessionId));
      }
      final supported = [
        for (final record in log.attempts) record.identity.attemptId,
      ];
      expect(supported.toSet(), hasLength(supported.length));
      expect(ledger.offered, containsAll(supported));
      expect(supported, containsAll(ledger.acquired));
      expect({
        ...ledger.acquired,
        ...ledger.acquisitionUncertain,
      }, containsAll(supported));
      expect(
        ledger.decided,
        containsAll([
          for (final record in log.records)
            if (record is AcquisitionProbeServedRecord)
              record.identity.attemptId,
        ]),
        reason: 'a probe is served by presenting an ordinary attempt',
      );

      store.readOnly = true;
      final PracticeSession fresh;
      try {
        fresh = await _open(ledger, sessionId: 'reading');
      } finally {
        store.readOnly = false;
      }
      final shown = ledger.shown;
      final pending = fresh.pending?.attemptId;
      if (shown != null && !attempts.contains(shown.id)) {
        expect(
          pending,
          ledger.abandonMayHaveLanded ? anyOf(shown.id, isNull) : shown.id,
          reason: 'what was shown is still pending',
        );
      } else if (!ledger.unshownPending) {
        expect(pending, isNull, reason: 'nothing is waiting to be answered');
      }

      final live = session;
      // Every store read answers here, so whatever a write left uncertain
      // has been settled by reading, and the session has to agree with what
      // it reads.
      if (ledger == current && live != null) {
        expect(learnerStateHash(fresh.state), learnerStateHash(live.state));
        expect(fresh.journal.length, live.journal.length);
        expect(fresh.acquisitionJournal.length, live.acquisitionJournal.length);
      }
    }
  }
}

Future<void> _refused(Future<Object?> Function() call, String why) async {
  try {
    await call();
  } on PracticeStateError {
    return;
  }
  fail('not refused: $why');
}

/// Runs [body] and then the durable checks, with any [Error] reported as a
/// failure the runner can shrink.
///
/// The runner tears down before it reports a falsified sequence, so a failure
/// marks [Device.reached] falsified on its way out.
Future<void> _command(Device device, Future<void> Function() body) async {
  try {
    try {
      await body();
      await device.check();
    } on TestFailure {
      rethrow;
    } catch (error, stackTrace) {
      fail('$error\n$stackTrace');
    }
  } on TestFailure {
    device.reached.falsified(null);
    rethrow;
  }
}

Action<Device, Device, T, void> _action<T>(
  String description,
  Arbitrary<T> arbitrary,
  Future<void> Function(Device, T) body,
) => Action(
  description,
  arbitrary,
  nextState: (_, _) {},
  run: (device, value) => _command(device, () => body(device, value)),
);

Action0<Device, Device, void> _step(
  String description,
  Future<void> Function(Device) body,
) => Action0(
  description,
  nextState: (_) {},
  run: (device) => _command(device, () => body(device)),
);

class TransactionBehavior extends Behavior<Device, Device> {
  final Reached<String> reached;

  TransactionBehavior(this.reached);

  @override
  Device initialState() => Device(reached);

  @override
  Device createSystem(Device state) => state;

  @override
  void destroySystem(Device system) {}

  @override
  void tearDownAll() => reached.check();

  @override
  List<Command<Device, Device>> generateCommands(Device state) => [
    _action(
      'decide',
      combine2(integer(min: 1, max: 3 * 24 * 60), boolean()),
      (device, value) => device.decide(value.$1, value.$2),
    ),
    _step('acknowledge', (device) => device.acknowledge()),
    _action(
      'close',
      choiceOf(Closing.values),
      (device, how) => device.close(how),
    ),
    _step('close acquisition', (device) => device.closeAcquisition()),
    _step('abandon', (device) => device.abandon()),
    _step('checkpoint', (device) => device.checkpoint()),
    _action(
      'arm a failure',
      combine2(choiceOf(Boundary.values), boolean()),
      (device, value) async => device.arm(value.$1, value.$2),
    ),
    _step('relaunch', (device) => device.relaunch()),
    _step('switch profile', (device) => device.switchProfile()),
  ];
}

void main() {
  property('generated practice keeps every transaction whole', () {
    runBehavior(
      TransactionBehavior(
        Reached({
          'presented',
          'offered acquisition',
          'closed played',
          'closed declined',
          'closed unmeasured',
          'closed acquisition',
          'abandoned',
          'checkpointed',
          'resumed a pending attempt',
          'decision not saved',
          'a retried close finished',
          'a retried acquisition close finished',
          'a relaunch found an uncertain close durable',
          'refused to abandon history',
          'a close failed after its attempt became history',
          'recovered an unshown decision',
          'abandon not saved',
        }),
      ),
      seed: propertySeed,
      maxCycles: propertyBudget(30),
      maxSteps: 40,
    );
  });
}
