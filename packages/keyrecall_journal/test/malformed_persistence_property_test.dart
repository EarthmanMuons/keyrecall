import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'checkpoint_recovery_property_test.dart'
    show Step, anyGenesis, anyStep, historyOf, model;
import 'record_round_trip_property_test.dart' show anyRecord;
import 'support/journal_arbitraries.dart';

/// How a stored value is damaged.
enum Damage { remove, retype, unknownToken, nonFinite, outOfRange }

/// One damage, landing a fraction of the way through the tree's nodes, with a
/// choice among that damage's replacements.
typedef Mutation = (Damage, double, int);

final Arbitrary<Mutation> anyMutation = combine3(
  choiceOf(Damage.values),
  float(min: 0, max: 1),
  integer(min: 0, max: 1 << 10),
);

/// Every node under [node], as the keys and indexes that reach it.
List<List<Object>> pathsIn(Object? node, [List<Object> at = const []]) => [
  if (at.isNotEmpty) at,
  if (node is Map<String, Object?>)
    for (final MapEntry(:key, :value) in node.entries)
      ...pathsIn(value, [...at, key]),
  if (node is List<Object?>)
    for (final (index, value) in node.indexed)
      ...pathsIn(value, [...at, index]),
];

const List<Object?> _otherTypes = ['text', 7, 0.5, true, <Object?>[], null];

/// [json] with [mutation] applied to one node, among those under [within].
///
/// Returns what was done, for a failure to name.
(Map<String, Object?>, String) damaged(
  Map<String, Object?> json,
  Mutation mutation, {
  List<Object> within = const [],
}) {
  final copy = jsonDecode(jsonEncode(json)) as Map<String, Object?>;
  final (damage, where, pick) = mutation;
  final paths = [
    for (final path in pathsIn(copy))
      if (path.length > within.length &&
          [
            for (var i = 0; i < within.length; i++) path[i] == within[i],
          ].every((same) => same))
        path,
  ];
  if (paths.isEmpty) return (copy, 'nothing to damage');
  final path = paths[(where * paths.length).floor().clamp(0, paths.length - 1)];
  Object? parent = copy;
  for (final step in path.take(path.length - 1)) {
    parent = parent is Map ? parent[step] : (parent as List)[step as int];
  }
  final key = path.last;
  final current = parent is Map ? parent[key] : (parent as List)[key as int];
  void put(Object? value) => parent is Map
      ? parent[key] = value
      : (parent as List)[key as int] = value;

  switch (damage) {
    case Damage.remove:
      parent is Map
          ? parent.remove(key)
          : (parent as List).removeAt(key as int);
    case Damage.retype:
      put(
        _otherTypes.firstWhere(
          (other) =>
              other.runtimeType != current.runtimeType &&
              !(other is num && current is num),
          orElse: () => <String, Object?>{},
        ),
      );
    case Damage.unknownToken:
      put('NOT_A_KNOWN_VALUE');
    case Damage.nonFinite:
      put([double.nan, double.infinity, double.negativeInfinity][pick % 3]);
    case Damage.outOfRange:
      put([-1, -0.5, 1.5, 1e300, 9007199254740993][pick % 5]);
  }
  return (copy, '${damage.name} at ${path.join('.')} (was $current)');
}

/// Whether two JSON trees say the same thing, where an absent key and a null
/// one are the same and a number is its value however it was written.
bool sameJson(Object? a, Object? b) => switch ((a, b)) {
  (final num x, final num y) => x == y,
  (final List<Object?> x, final List<Object?> y) =>
    x.length == y.length &&
        ([
              for (var i = 0; i < x.length; i++) sameJson(x[i], y[i]),
            ].every((same) => same) ||
            _sameElements(x, y)),
  (final Map<String, Object?> x, final Map<String, Object?> y) => {
    ...x.keys,
    ...y.keys,
  }.every((key) => sameJson(x[key], y[key])),
  _ => a == b,
};

/// Whether [x] and [y] hold the same elements in some order, which is how a
/// set written in canonical order reads back after one element changed.
bool _sameElements(List<Object?> x, List<Object?> y) {
  final unmatched = [...y];
  for (final element in x) {
    final partner = unmatched.indexWhere((other) => sameJson(element, other));
    if (partner < 0) return false;
    unmatched.removeAt(partner);
  }
  return true;
}

/// [decode] of [json] either refuses it as a format error or reads exactly
/// what it says, which [encode] writes back.
void refusedOrFaithful<T>(
  Map<String, Object?> json,
  String what,
  T Function(Map<String, Object?>) decode,
  Map<String, Object?> Function(T) encode,
  Reached<String> reached,
) {
  final T read;
  try {
    read = decode(json);
  } on JournalFormatException {
    reached.add('refused');
    return;
  } catch (error) {
    fail('$what: ${error.runtimeType} rather than a format error: $error');
  }
  reached.add('read as written');
  expect(
    sameJson(encode(read), json),
    isTrue,
    reason: '$what was read as something else: ${encode(read)}',
  );
}

final DateTime start = DateTime.utc(2026);

/// One way an attempt that reads perfectly well contradicts the journal it is
/// offered to.
enum Contradiction {
  otherProfile,
  skippedSequence,
  repeatedSequence,
  earlierTime,
  stalledIndex,
  reusedId,
}

/// A journal [historyOf] wrote, from generated practice.
typedef History = (
  (String, LearnerState Function(DateTime)),
  List<Exercise>,
  List<Step>,
);

final Arbitrary<History> anyHistory = combine3(
  anyGenesis,
  list(anyExercise, minLength: 1, maxLength: 3),
  list(anyStep, minLength: 1, maxLength: 6),
);

AttemptJournal journalOf(History history) =>
    historyOf(history.$1.$2, start, history.$2, history.$3).journal;

void main() {
  property('a damaged attempt is refused or read as written', () {
    final reached = Reached({'refused', 'read as written'});
    forAll(
      combine2(anyRecord, anyMutation),
      seed: propertySeed,
      maxExamples: propertyBudget(500),
      onFalsify: reached.falsified,
      tearDownAll: reached.check,
      failingOnErrors<(AttemptRecord, Mutation)>((value) {
        final (json, what) = damaged(value.$1.toJson(), value.$2);
        refusedOrFaithful(
          json,
          what,
          AttemptRecord.fromJson,
          (read) => read.toJson(),
          reached,
        );
      }),
    );
  });

  property('a damaged acquisition entry is refused or read as written', () {
    final reached = Reached({'refused', 'read as written'});
    forAll(
      combine3(anyAttempt, anyProbe, anyMutation),
      seed: propertySeed,
      maxExamples: propertyBudget(300),
      onFalsify: reached.falsified,
      tearDownAll: reached.check,
      failingOnErrors<
        (AcquisitionAttemptRecord, AcquisitionProbeServedRecord, Mutation)
      >((value) {
        final (attempt, probe, mutation) = value;
        final (attemptJson, attemptDamage) = damaged(
          attempt.toJson(),
          mutation,
        );
        refusedOrFaithful(
          attemptJson,
          attemptDamage,
          AcquisitionAttemptRecord.fromJson,
          (read) => read.toJson(),
          reached,
        );
        final (probeJson, probeDamage) = damaged(probe.toJson(), mutation);
        refusedOrFaithful(
          probeJson,
          probeDamage,
          AcquisitionProbeServedRecord.fromJson,
          (read) => read.toJson(),
          reached,
        );
      }),
    );
  });

  property('a damaged checkpoint state is refused or read as written', () {
    final reached = Reached({'refused', 'read as written'});
    forAll(
      combine4(
        anyGenesis,
        list(anyExercise, minLength: 1, maxLength: 3),
        list(anyStep, minLength: 1, maxLength: 6),
        anyMutation,
      ),
      seed: propertySeed,
      maxExamples: propertyBudget(100),
      onFalsify: reached.falsified,
      tearDownAll: reached.check,
      failingOnErrors<
        (
          (String, LearnerState Function(DateTime)),
          List<Exercise>,
          List<Step>,
          Mutation,
        )
      >((value) {
        final (genesis, exercises, steps, mutation) = value;
        final history = historyOf(genesis.$2, start, exercises, steps);
        final checkpoint = LearnerStateCheckpoint.after(
          history.journal,
          throughSequence: history.journal.length - 1,
          state: history.after.last,
          learnerModelVersion: model.params.modelVersion,
          genesisStateHash: learnerStateHash(history.initial),
        );

        // Damage that keeps the hash honest reaches the state's own reader.
        final (json, what) = damaged(
          checkpoint.toJson(),
          mutation,
          within: const ['state'],
        );
        try {
          json['content_hash'] = contentHash(json['state']);
        } on JournalFormatException {
          // Damage canonical JSON cannot hold cannot be stored either.
          reached.add('refused');
          return;
        }
        refusedOrFaithful(
          json,
          what,
          (json) => LearnerStateCheckpoint.fromJson(json, params: model.params),
          (read) => read.toJson(),
          reached,
        );

        // Damage that does not is refused by the hash, whatever it was.
        final (unhashed, _) = damaged(
          checkpoint.toJson(),
          mutation,
          within: const ['state'],
        );
        if (!sameJson(unhashed['state'], checkpoint.toJson()['state'])) {
          expect(
            () =>
                LearnerStateCheckpoint.fromJson(unhashed, params: model.params),
            throwsA(isA<JournalFormatException>()),
          );
        }
      }),
    );
  });

  property('a journal refuses an attempt that contradicts it, unchanged', () {
    forAll(
      combine2(anyHistory, choiceOf(Contradiction.values)),
      seed: propertySeed,
      maxExamples: propertyBudget(150),
      failingOnErrors<(History, Contradiction)>((value) {
        final (history, contradiction) = value;
        final journal = journalOf(history);
        final last = journal.records.last;
        final next = {
          ...last.toJson(),
          'journal_sequence': journal.length,
          'attempt_id': 'next',
          'index_in_session': last.identity.indexInSession + 1,
          'occurred_at': encodeTime(
            last.identity.occurredAt.add(const Duration(seconds: 1)),
          ),
        };
        expect(
          AttemptJournal.fromJsonLines(
            journal.toJsonLines(),
          ).append(AttemptRecord.fromJson(next)),
          isTrue,
          reason: 'the attempt contradicts nothing until it is changed',
        );

        final contradicting = AttemptRecord.fromJson({
          ...next,
          ...switch (contradiction) {
            Contradiction.otherProfile => {'profile_id': 'someone-else'},
            Contradiction.skippedSequence => {
              'journal_sequence': journal.length + 1,
            },
            Contradiction.repeatedSequence => {
              'journal_sequence': journal.length - 1,
            },
            Contradiction.earlierTime => {
              'occurred_at': encodeTime(
                last.identity.occurredAt.subtract(const Duration(seconds: 1)),
              ),
            },
            Contradiction.stalledIndex => {
              'index_in_session': last.identity.indexInSession,
            },
            Contradiction.reusedId => {
              'attempt_id': journal.records.first.identity.attemptId,
            },
          },
        });
        final lines = journal.toJsonLines();
        expect(
          () => journal.append(contradicting),
          throwsA(isA<JournalFormatException>()),
          reason: contradiction.name,
        );
        expect(journal.toJsonLines(), lines, reason: 'nothing moved');
        expect(
          () => AttemptJournal.fromJsonLines(
            '$lines${jsonEncode(contradicting.toJson())}\n',
          ),
          throwsA(isA<JournalFormatException>()),
          reason: 'stored, it refuses the whole journal',
        );
      }),
    );
  });

  property('a probe of a parent never attempted is refused, unchanged', () {
    forAll(
      combine3(anyAttempt, anyProbe, anyExercise),
      seed: propertySeed,
      maxExamples: propertyBudget(150),
      failingOnErrors<
        (AcquisitionAttemptRecord, AcquisitionProbeServedRecord, Exercise)
      >((value) {
        final (attempt, probe, elsewhere) = value;
        Map<String, Object?> placed(Map<String, Object?> json, int sequence) =>
            {
              ...json,
              'profile_id': 'learner',
              'attempt_id': 'entry-$sequence',
              'journal_sequence': sequence,
              'occurred_at': encodeTime(start.add(Duration(seconds: sequence))),
            };
        final log =
            AcquisitionJournal(
              AcquisitionJournalHeader(profileId: 'learner', createdAt: start),
            )..append(
              AcquisitionAttemptRecord.fromJson(placed(attempt.toJson(), 0)),
            );
        AcquisitionProbeServedRecord probeOf(Exercise parent) =>
            AcquisitionProbeServedRecord.fromJson({
              ...placed(probe.toJson(), 1),
              'parent': encodeExercise(parent),
            });

        if (elsewhere != attempt.parent) {
          final lines = log.toJsonLines();
          expect(
            () => log.append(probeOf(elsewhere)),
            throwsA(isA<JournalFormatException>()),
          );
          expect(log.toJsonLines(), lines, reason: 'nothing moved');
        }
        expect(log.append(probeOf(attempt.parent)), isTrue);
      }),
    );
  });

  property(
    'a checkpoint whose boundary the journal contradicts is rejected',
    () {
      forAll(
        combine3(anyHistory, integer(min: 0, max: 5), integer(min: 0, max: 99)),
        seed: propertySeed,
        maxExamples: propertyBudget(100),
        failingOnErrors<(History, int, int)>((value) {
          final (history, field, at) = value;
          final written = historyOf(
            history.$1.$2,
            start,
            history.$2,
            history.$3,
          );
          final journal = written.journal;
          final through = at % journal.length;
          final genesis = learnerStateHash(written.initial);
          final checkpoint = LearnerStateCheckpoint.after(
            journal,
            throughSequence: through,
            state: written.after[through],
            learnerModelVersion: model.params.modelVersion,
            genesisStateHash: genesis,
          );
          CheckpointRejection? validated(Map<String, Object?> json) =>
              validateCheckpointAgainstJournal(
                LearnerStateCheckpoint.fromJson(json, params: model.params),
                journal: journal,
                learnerModelVersion: model.params.modelVersion,
                genesisStateHash: genesis,
              );

          final json = checkpoint.toJson();
          expect(validated(json), isNull, reason: 'the checkpoint as written');
          final (key, wrong) = switch (field) {
            0 => ('profile_id', 'someone-else'),
            1 => ('learner_model_version', 'another model'),
            2 => (
              'through_journal_sequence',
              (through + 1) % (journal.length + 1),
            ),
            3 => ('through_attempt_id', 'another attempt'),
            4 => ('covers_history_hash', 'another history'),
            _ => (
              'covers_through',
              encodeTime(start.subtract(const Duration(days: 1))),
            ),
          };
          expect(
            validated({...json, key: wrong}),
            isNotNull,
            reason: 'a checkpoint whose $key disagrees with the journal',
          );
        }),
      );
    },
  );
}
