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
/// A mature full-catalog decision costs a fifth of a second on a mid-range
/// phone, and computing it elsewhere costs nothing but the state that travels:
/// the learner state and the sitting cross by copy, the candidate envelope
/// never moves because the worker holds the scope, and only the winning
/// candidate comes back.
///
/// Disposable by construction. It owns no durability and no lifecycle policy:
/// a worker that dies mid-decision fails that request and nothing else, and the
/// session decides again from the state it never gave up.
class IsolateScheduler implements SchedulerHost {
  final LearnerParams learnerParams;
  final SchedulerConfig config;

  _Worker? _worker;

  IsolateScheduler({
    this.learnerParams = v1PrototypeLearnerParams,
    this.config = v1SchedulerConfig,
  });

  @override
  Future<void> bind(
    ResolvedPracticeScope scope,
    PracticeEntryPolicy entry,
  ) async {
    await dispose();
    _worker = await _Worker.start(
      scope: scope,
      entry: entry,
      learnerParams: learnerParams,
      config: config,
    );
  }

  @override
  Future<void> dispose() async {
    _worker?.stop();
    _worker = null;
  }

  @override
  Future<SchedulerVerdict> decide({
    required int epoch,
    required LearnerState state,
    required SessionState session,
    required List<String> dueRequirementIds,
    required DateTime at,
    AcquisitionFloor? acquisitionFloor,
  }) {
    final worker = _worker;
    if (worker == null) {
      throw StateError('no scope is bound; bind one before deciding');
    }
    return worker.decide(
      _DecisionRequest(
        epoch: epoch,
        state: state,
        session: session,
        dueRequirementIds: dueRequirementIds,
        at: at,
        acquisitionFloor: acquisitionFloor,
      ),
    );
  }
}

class _DecisionRequest {
  final int epoch;
  final LearnerState state;
  final SessionState session;
  final List<String> dueRequirementIds;
  final DateTime at;
  final AcquisitionFloor? acquisitionFloor;

  const _DecisionRequest({
    required this.epoch,
    required this.state,
    required this.session,
    required this.dueRequirementIds,
    required this.at,
    required this.acquisitionFloor,
  });
}

class _DecisionResponse {
  final int epoch;
  final CandidateTrace? chosen;
  final BlockedReason? blockedReason;
  final bool guidanceProbeAvailable;
  final bool guidanceProbeSelected;

  const _DecisionResponse({
    required this.epoch,
    required this.chosen,
    required this.blockedReason,
    required this.guidanceProbeAvailable,
    required this.guidanceProbeSelected,
  });

  SchedulerVerdict get verdict {
    final effect = SittingDecisionEffect(
      guidanceProbeAvailable: guidanceProbeAvailable,
      guidanceProbeSelected: guidanceProbeSelected,
    );
    return chosen == null
        ? SchedulerVerdict.blocked(blockedReason!, epoch: epoch, effect: effect)
        : SchedulerVerdict.selected(chosen!, epoch: epoch, effect: effect);
  }
}

/// One spawned isolate holding one scope, and the port pair that talks to it.
class _Worker {
  final Isolate _isolate;
  final SendPort _requests;
  final ReceivePort _responses;

  /// The request this worker is answering, if any.
  ///
  /// One at a time, because a session decides one slot at a time: a second
  /// request cannot exist while the first is unanswered.
  Completer<_DecisionResponse>? _waiting;

  _Worker._(this._isolate, this._requests, this._responses);

  static Future<_Worker> start({
    required ResolvedPracticeScope scope,
    required PracticeEntryPolicy entry,
    required LearnerParams learnerParams,
    required SchedulerConfig config,
  }) async {
    final responses = ReceivePort();
    final ready = Completer<SendPort>();
    final isolate = await Isolate.spawn(_serve, (
      responses.sendPort,
      scope,
      entry,
      learnerParams,
      config,
    ));
    late final _Worker worker;
    responses.listen((message) {
      if (message is SendPort) {
        ready.complete(message);
      } else {
        worker._answer(message as _DecisionResponse);
      }
    });
    return worker = _Worker._(isolate, await ready.future, responses);
  }

  Future<SchedulerVerdict> decide(_DecisionRequest request) {
    final completer = Completer<_DecisionResponse>();
    _waiting = completer;
    _requests.send(request);
    return completer.future.then((response) => response.verdict);
  }

  void _answer(_DecisionResponse response) {
    final completer = _waiting;
    _waiting = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete(response);
    }
  }

  void stop() {
    final completer = _waiting;
    _waiting = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const SchedulerWorkerLost());
    }
    _responses.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  static Future<void> _serve(
    (
      SendPort,
      ResolvedPracticeScope,
      PracticeEntryPolicy,
      LearnerParams,
      SchedulerConfig,
    )
    start,
  ) async {
    final (replies, scope, entry, learnerParams, config) = start;
    final pipeline = SchedulerPipeline(
      learner: LearnerModel(params: learnerParams),
      config: config,
    );
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
        practiceEntryPolicy: entry,
      );
      replies.send(
        _DecisionResponse(
          epoch: request.epoch,
          chosen: switch (slot.result) {
            CandidateSelected(:final candidate) => candidate,
            SelectionBlocked() => null,
          },
          blockedReason: switch (slot.result) {
            SelectionBlocked(:final reason) => reason,
            CandidateSelected() => null,
          },
          guidanceProbeAvailable: slot.guidanceProbeAvailable,
          guidanceProbeSelected: slot.guidanceProbeSelected,
        ),
      );
    }
    requests.close();
  }
}
