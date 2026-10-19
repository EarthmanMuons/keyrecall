import 'package:meta/meta.dart';

import 'canonical_json.dart';
import 'schema.dart';

/// What one allocation opportunity did for the requirements in scope, in
/// scope order: those its exercise served, and those actionable and missed.
///
/// An acquisition offer serves no requirement.
@immutable
class AllocationEvidence {
  final List<String> served;
  final List<String> missed;

  /// Throws [ArgumentError] when a requirement is named twice, in either list
  /// or both.
  AllocationEvidence({
    required Iterable<String> served,
    required Iterable<String> missed,
  }) : served = List.unmodifiable(served),
       missed = List.unmodifiable(missed) {
    final named = <String>{};
    for (final id in [...this.served, ...this.missed]) {
      if (!named.add(id)) {
        throw ArgumentError.value(id, 'requirementId', 'named twice');
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AllocationEvidence &&
      _sameOrder(served, other.served) &&
      _sameOrder(missed, other.missed);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(served), Object.hashAll(missed));

  @override
  String toString() => 'AllocationEvidence(served: $served, missed: $missed)';

  static bool _sameOrder(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);
}

/// Why a recorded event carries no allocation evidence.
enum AllocationGap {
  /// Written before the format carried allocation.
  legacy('legacy'),

  /// An acquisition attempt recorded after ordinary attempts its decision
  /// did not see, so its evidence cannot be placed in the fold.
  staleAcquisition('stale_acquisition'),

  /// Written by a decision path that computed no evidence.
  notInstrumented('not_instrumented');

  const AllocationGap(this.id);

  final String id;

  static AllocationGap fromId(String id) => values.firstWhere(
    (gap) => gap.id == id,
    orElse: () => throw JournalFormatException('unknown allocation gap $id'),
  );
}

/// Which scheduling policy a profile was assigned when a decision was made,
/// and which one made it.
@immutable
class AllocationPolicyIdentity {
  final String assigned;
  final String effective;

  AllocationPolicyIdentity({required this.assigned, required this.effective}) {
    for (final (name, id) in [
      ('assigned', assigned),
      ('effective', effective),
    ]) {
      if (id.isEmpty) throw ArgumentError.value(id, name, 'must not be empty');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AllocationPolicyIdentity &&
      other.assigned == assigned &&
      other.effective == effective;

  @override
  int get hashCode => Object.hash(assigned, effective);
}

/// How much committed history the counters a decision read had folded: the
/// ordinary attempts and the acquisition attempts before it.
@immutable
class AllocationBasis {
  final int attempts;
  final int acquisitionAttempts;

  AllocationBasis({required this.attempts, required this.acquisitionAttempts}) {
    if (attempts < 0 || acquisitionAttempts < 0) {
      throw ArgumentError('an allocation basis cannot be negative');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AllocationBasis &&
      other.attempts == attempts &&
      other.acquisitionAttempts == acquisitionAttempts;

  @override
  int get hashCode => Object.hash(attempts, acquisitionAttempts);

  @override
  String toString() => 'AllocationBasis($attempts, $acquisitionAttempts)';
}

/// What a committed event says about allocation.
@immutable
sealed class AllocationRecord {
  const AllocationRecord();

  /// The policies in force, or null for a record written before the format
  /// carried them.
  AllocationPolicyIdentity? get policy;

  Map<String, Object?> toJson();

  /// Throws [JournalFormatException] for anything unreadable.
  static AllocationRecord fromJson(
    Map<String, Object?> json, {
    String? location,
  }) => located(
    () {
      final assigned = asOptionalString(
        json['assigned_policy'],
        'assigned_policy',
        location: location,
      );
      final effective = asOptionalString(
        json['effective_policy'],
        'effective_policy',
        location: location,
      );
      if ((assigned == null) != (effective == null)) {
        throw JournalFormatException(
          'an allocation record names both policies or neither',
          location: location,
        );
      }
      final policy = assigned == null
          ? null
          : AllocationPolicyIdentity(assigned: assigned, effective: effective!);
      final gap = json['gap'];
      final evidence = json['evidence'];
      if ((gap == null) == (evidence == null)) {
        throw JournalFormatException(
          'an allocation record carries evidence or names why it has none',
          location: location,
        );
      }
      if (gap != null) {
        return AllocationUnobserved(
          AllocationGap.fromId(asString(gap, 'gap', location: location)),
          policy: policy,
        );
      }
      if (policy == null) {
        throw JournalFormatException(
          'allocation evidence names the policies it was recorded under',
          location: location,
        );
      }
      final evidenceJson = asMap(evidence, 'evidence', location: location);
      final basis = requireMap(json, 'basis', location: location);
      List<String> ids(String key) => switch (evidenceJson[key]) {
        final List<Object?> list => [
          for (final id in list) asString(id, key, location: location),
        ],
        _ => throw JournalFormatException(
          'expected a list at "$key"',
          location: location,
        ),
      };
      return AllocationObserved(
        policy: policy,
        basis: AllocationBasis(
          attempts: requireInt(basis, 'attempts', location: location),
          acquisitionAttempts: requireInt(
            basis,
            'acquisition_attempts',
            location: location,
          ),
        ),
        evidence: AllocationEvidence(
          served: ids('served'),
          missed: ids('missed'),
        ),
      );
    },
    'allocation',
    location: location,
  );
}

/// An event whose decision recorded what it did for every requirement.
final class AllocationObserved extends AllocationRecord {
  @override
  final AllocationPolicyIdentity policy;

  final AllocationBasis basis;
  final AllocationEvidence evidence;

  const AllocationObserved({
    required this.policy,
    required this.basis,
    required this.evidence,
  });

  @override
  Map<String, Object?> toJson() => {
    'assigned_policy': policy.assigned,
    'effective_policy': policy.effective,
    'basis': {
      'attempts': basis.attempts,
      'acquisition_attempts': basis.acquisitionAttempts,
    },
    'evidence': {'served': evidence.served, 'missed': evidence.missed},
  };

  @override
  bool operator ==(Object other) =>
      other is AllocationObserved &&
      other.policy == policy &&
      other.basis == basis &&
      other.evidence == evidence;

  @override
  int get hashCode => Object.hash(policy, basis, evidence);
}

/// An event that contributes nothing to allocation, and why.
///
/// Not an event with nothing served or missed: that is observed, and this
/// says no observation can be applied.
final class AllocationUnobserved extends AllocationRecord {
  final AllocationGap gap;

  @override
  final AllocationPolicyIdentity? policy;

  const AllocationUnobserved(this.gap, {this.policy});

  static const legacy = AllocationUnobserved(AllocationGap.legacy);

  @override
  Map<String, Object?> toJson() => {
    'assigned_policy': policy?.assigned,
    'effective_policy': policy?.effective,
    'gap': gap.id,
  };

  @override
  bool operator ==(Object other) =>
      other is AllocationUnobserved &&
      other.gap == gap &&
      other.policy == policy;

  @override
  int get hashCode => Object.hash(gap, policy);
}
