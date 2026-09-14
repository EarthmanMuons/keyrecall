import 'dart:async';
import 'dart:isolate';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'scheduler_host.dart';

/// Thrown where a decision was being computed on a worker that went away.
///
/// Nothing was applied and nothing was written: the session holds the
/// authoritative state, so asking again on a fresh worker is the whole of the
/// recovery.
class SchedulerWorkerLost implements Exception {
  final Object? cause;

  const SchedulerWorkerLost([this.cause]);

  @override
  String toString() => 'SchedulerWorkerLost${cause == null ? '' : ': $cause'}';
}

/// Decides on a worker isolate, so the isolate that draws is free while it
/// happens.
///
/// The learner state and the sitting cross by copy, the candidate envelope
/// never moves because the worker holds the scope, and the winner comes back
/// with a compact competition report.
///
/// Disposable by construction. It owns no durability and no lifecycle policy:
/// a worker that dies mid-decision fails that request and nothing else,
/// however it died, and the session decides again from the state it never gave
/// up.
///
/// One host belongs to one sitting. Binding replaces the scope the worker
/// holds, so a host two sittings share decides both of their slots against
/// whichever scope bound last.
class IsolateScheduler implements SchedulerHost {
  _Worker? _worker;

  /// Names each binding, so a startup that was superseded or disposed while
  /// its isolate was spawning does not install its worker over the one that
  /// replaced it.
  int _bindings = 0;

  @override
  Future<void> bind({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  }) async {
    // Named before yielding. A generation taken after an await is whatever the
    // lifecycle did during it, so a binding disposed while spawning would come
    // back holding the number that disposal issued and install itself anyway.
    final binding = _invalidate();

    final _Worker worker;
    try {
      worker = await _Worker.start(
        scope: scope,
        entry: entry,
        learner: learner,
        config: config,
      );
    } on SchedulerWorkerLost {
      rethrow;
    } catch (error) {
      throw SchedulerWorkerLost(error);
    }

    if (binding != _bindings) {
      // Disposed or bound again while this one was spawning. The isolate it
      // just made answers a scope nobody is practicing under.
      worker.stop();
      return;
    }
    worker.onLost = () {
      if (identical(_worker, worker)) _worker = null;
    };
    if (worker.isLost) {
      _worker = null;
      throw const SchedulerWorkerLost('the worker died during startup');
    }
    _worker = worker;
  }

  @override
  Future<void> dispose() async => _invalidate();

  /// Ends whatever is bound, and names the operation replacing it.
  ///
  /// Synchronous, and the only thing that retires a worker. Binding and
  /// disposal are one question asked twice, and an asynchronous lifecycle
  /// operation calling another is what makes the ordering hard to see.
  int _invalidate() {
    final worker = _worker;
    _worker = null;
    worker?.stop();
    return ++_bindings;
  }

  @override
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    Set<Exercise>? attemptedExercises,
    Map<ExecutionContext, int> executionEvidenceRevisions = const {},
  }) async {
    final worker = _worker;
    if (worker == null) {
      throw StateError('no scope is bound; bind one before deciding');
    }
    return worker.decide(
      _DecisionRequest(
        id: worker.nextRequestId(),
        epoch: epoch,
        state: state,
        session: session,
        dueRequirementIds: dueRequirementIds,
        at: at,
        acquisitionFloor: acquisitionFloor,
        acquisitionFamilyFloor: acquisitionFamilyFloor,
        acquisition: acquisition,
        attemptedExercises: attemptedExercises,
        executionEvidenceRevisions: executionEvidenceRevisions,
      ),
    );
  }
}

class _DecisionRequest {
  /// Which request this is, echoed by the answer.
  ///
  /// What correlates the two. A worker answering whatever it was last asked
  /// cannot tell one caller's verdict from another's, and a verdict handed to
  /// the wrong caller is valid and wrong.
  final int id;

  final int epoch;
  final LearnerState state;
  final SessionState session;
  final List<String> dueRequirementIds;
  final DateTime at;
  final AcquisitionFloor? acquisitionFloor;
  final AcquisitionFloor? acquisitionFamilyFloor;
  final AcquisitionProgress? acquisition;
  final Set<Exercise>? attemptedExercises;
  final Map<ExecutionContext, int> executionEvidenceRevisions;

  const _DecisionRequest({
    required this.id,
    required this.epoch,
    required this.state,
    required this.session,
    required this.dueRequirementIds,
    required this.at,
    required this.acquisitionFloor,
    required this.acquisitionFamilyFloor,
    required this.acquisition,
    required this.attemptedExercises,
    required this.executionEvidenceRevisions,
  });
}

class _DecisionResponse {
  final int id;
  final String diagnostics;
  final int epoch;
  final CandidateTrace? chosen;
  final BlockedReason? blockedReason;
  final AcquisitionTask? acquisitionTask;
  final Exercise? displacedByAcquisition;
  final SelectionEffect effect;

  const _DecisionResponse({
    required this.id,
    required this.diagnostics,
    required this.epoch,
    required this.chosen,
    required this.blockedReason,
    required this.acquisitionTask,
    required this.displacedByAcquisition,
    required this.effect,
  });

  SchedulerVerdict get verdict {
    if (acquisitionTask case final task?) {
      return SchedulerVerdict.acquisition(
        task,
        epoch: epoch,
        effect: effect,
        diagnostics: diagnostics,
        displacedByAcquisition: displacedByAcquisition,
      );
    }
    return chosen == null
        ? SchedulerVerdict.blocked(
            blockedReason!,
            epoch: epoch,
            effect: effect,
            diagnostics: diagnostics,
          )
        : SchedulerVerdict.selected(
            chosen!,
            epoch: epoch,
            effect: effect,
            diagnostics: diagnostics,
          );
  }
}

/// One spawned isolate holding one scope, and the port pair that talks to it.
///
/// Three states and no others: starting, ready, and lost. Lost is terminal and
/// covers every way a worker can go away, whether it was stopped or died,
/// because a caller waiting on an answer needs the same thing from all of them.
class _Worker {
  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _responses;

  /// The requests this worker has not answered, by id.
  final Map<int, Completer<_DecisionResponse>> _waiting = {};

  int _requestIds = 0;
  bool _lost = false;

  /// Told when this worker goes away on its own, so the host stops offering it.
  void Function()? onLost;

  _Worker._(this._isolate, this._requests, this._responses);

  static Future<_Worker> start({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerModel learner,
    required SchedulerConfig config,
  }) async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    _Worker? started;
    // A worker can be lost before there is a worker to lose it. Startup
    // failure and death during startup are the same fact arriving early, and
    // both have to reach the caller: without this it waits on a port nothing
    // will ever send to.
    SchedulerWorkerLost? lostAtStartup;
    void lose(SchedulerWorkerLost cause) {
      if (started case final worker?) {
        worker._lose(cause);
        return;
      }
      lostAtStartup ??= cause;
      if (!ready.isCompleted) ready.completeError(cause);
    }

    // An isolate that fails to start, throws while deciding, or exits for any
    // other reason reports here.
    responses.listen((message) {
      switch (message) {
        case SendPort():
          if (!ready.isCompleted) ready.complete(message);
        case _DecisionResponse():
          started?._answer(message);
        case List():
          // The pair an uncaught error in the isolate sends: the error and its
          // stack, both already strings.
          lose(SchedulerWorkerLost(message.first));
        case _:
          lose(const SchedulerWorkerLost('the worker exited'));
      }
    });

    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _serve,
        (responses.sendPort, scope, entry, learner, config),
        onError: responses.sendPort,
        onExit: responses.sendPort,
      );
    } catch (_) {
      responses.close();
      rethrow;
    }

    final SendPort requests;
    try {
      requests = await ready.future;
    } catch (_) {
      responses.close();
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    }
    started = _Worker._(isolate, requests, responses);
    if (lostAtStartup case final cause?) started._lose(cause);
    return started;
  }

  /// Whether this worker is gone, however it went.
  bool get isLost => _lost;

  int nextRequestId() => ++_requestIds;

  Future<SchedulerVerdict> decide(_DecisionRequest request) {
    if (_lost) return Future.error(const SchedulerWorkerLost());
    // One at a time, because a session decides one slot at a time. Two
    // overlapping requests are a caller deciding two slots at once, which is a
    // question about which slot the session is on rather than one a worker can
    // answer.
    if (_waiting.isNotEmpty) {
      return Future.error(
        StateError('a decision is already in flight on this worker'),
      );
    }
    final completer = Completer<_DecisionResponse>();
    _waiting[request.id] = completer;
    _requests.send(request);
    return completer.future.then((response) => response.verdict);
  }

  void _answer(_DecisionResponse response) {
    final completer = _waiting.remove(response.id);
    if (completer != null && !completer.isCompleted) {
      completer.complete(response);
    }
  }

  /// Ends this worker deliberately.
  void stop() => _lose(const SchedulerWorkerLost(), announce: false);

  /// Ends this worker, failing whatever it was answering.
  void _lose(SchedulerWorkerLost cause, {bool announce = true}) {
    if (_lost) return;
    _lost = true;
    final waiting = _waiting.values.toList();
    _waiting.clear();
    for (final completer in waiting) {
      if (!completer.isCompleted) completer.completeError(cause);
    }
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
    if (announce) onLost?.call();
  }

  static Future<void> _serve(
    (
      SendPort,
      ResolvedPracticeScope,
      PracticeEntryPolicy,
      LearnerModel,
      SchedulerConfig,
    )
    start,
  ) async {
    final (replies, scope, entry, learner, config) = start;
    final pipeline = SchedulerPipeline(learner: learner, config: config);
    final emphasis = goalEmphasisOf(scope);
    final requests = ReceivePort();
    replies.send(requests.sendPort);
    await for (final message in requests) {
      if (message == null) break;
      final request = message as _DecisionRequest;
      final slot = pipeline.evaluateSlot(
        state: request.state,
        session: request.session,
        candidates: candidatesDueIn(scope, request.dueRequirementIds),
        at: request.at,
        acquisitionFloor: request.acquisitionFloor,
        acquisitionFamilyFloor: request.acquisitionFamilyFloor,
        acquisition: request.acquisition,
        attemptedExercises: request.attemptedExercises,
        executionEvidenceRevisions: request.executionEvidenceRevisions,
        practiceEntryPolicy: entry,
        emphasis: emphasis,
      );
      replies.send(
        _DecisionResponse(
          id: request.id,
          diagnostics: slot.result.diagnostics,
          epoch: request.epoch,
          chosen: switch (slot.result) {
            CandidateSelected(:final candidate) => candidate,
            SelectionBlocked() || AcquisitionOffered() => null,
          },
          blockedReason: switch (slot.result) {
            SelectionBlocked(:final reason) => reason,
            CandidateSelected() || AcquisitionOffered() => null,
          },
          acquisitionTask: switch (slot.result) {
            AcquisitionOffered(:final task) => task,
            CandidateSelected() || SelectionBlocked() => null,
          },
          displacedByAcquisition: switch (slot.result) {
            AcquisitionOffered(:final displaced) => displaced,
            CandidateSelected() || SelectionBlocked() => null,
          },
          effect: SelectionEffect.of(slot.result),
        ),
      );
    }
    requests.close();
  }
}
