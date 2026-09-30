import 'attempt_closure.dart';
import 'schema.dart';

/// Brings a persisted attempt forward to [attemptSchemaVersion].
///
/// Pure and total: it reads one record's JSON and returns the current shape, or
/// throws. A journal is the historical source of truth, so an upgrade may add
/// what the old format implied and must never guess at what it did not say.
///
/// Throws [JournalFormatException] for a version this build cannot upgrade.
Map<String, Object?> upgradeAttemptJson(Map<String, Object?> json) =>
    json['schema_version'] == attemptSchemaVersion
    ? json
    : _version8To9(_attemptToVersion8(json));

Map<String, Object?> _attemptToVersion8(Map<String, Object?> json) {
  final version = json['schema_version'];
  return switch (version) {
    8 => json,
    7 => _version7To8(json),
    6 => _version7To8(_version6To7(json)),
    5 => _version7To8(_version6To7(_version5To6(json))),
    4 => _version7To8(_version6To7(_version5To6(_version4To5(json)))),
    3 => _version7To8(
      _version6To7(_version5To6(_version4To5(_version3To4(json)))),
    ),
    2 => _version7To8(
      _version6To7(
        _version5To6(_version4To5(_version3To4(_version2To3(json)))),
      ),
    ),
    1 => _version7To8(
      _version6To7(
        _version5To6(
          _version4To5(_version3To4(_version2To3(_version1To2(json)))),
        ),
      ),
    ),
    _ => throw JournalFormatException(
      'attempt schema version $version is not upgradable by this build, which '
      'writes version $attemptSchemaVersion',
    ),
  };
}

/// Brings a persisted journal header forward.
///
/// A header is stamped with the same version as the records it introduces,
/// even though its own fields have never changed. Reading one has to accept
/// every version the records can be upgraded from, or a readable journal is
/// rejected at its first line.
///
/// Throws [JournalFormatException] for a version this build cannot upgrade.
Map<String, Object?> upgradeJournalHeaderJson(Map<String, Object?> json) =>
    _stampedForward(json, 'journal header');

/// Brings a persisted pending decision forward.
///
/// Nothing in a pending decision changed between versions: it names an
/// exercise that was shown and the state it was chosen from, and neither an
/// outcome nor a closure was ever part of it. It carries the attempt version
/// because it becomes an attempt.
///
/// Throws [JournalFormatException] for a version this build cannot upgrade.
Map<String, Object?> upgradePendingDecisionJson(Map<String, Object?> json) =>
    json['schema_version'] == attemptSchemaVersion
    ? json
    : _version8To9(_pendingDecisionToVersion8(json));

Map<String, Object?> _pendingDecisionToVersion8(Map<String, Object?> json) =>
    switch (json['schema_version']) {
      8 => json,
      7 => _version7To8(json),
      6 => _version7To8(_version6To7(json)),
      5 => _version7To8(_version6To7(_version5To6(json))),
      4 => _version7To8(_version6To7(_version5To6(_version4To5(json)))),
      3 => _version7To8(
        _version6To7(_version5To6(_version4To5(_version3To4(json)))),
      ),
      2 => _version7To8(
        _version6To7(
          _version5To6(_version4To5(_version3To4(_version2To3(json)))),
        ),
      ),
      1 => _version7To8(
        _version6To7(
          _version5To6(
            _version4To5(
              _version3To4(
                _version2To3(_stampedForward(json, 'pending decision', to: 2)),
              ),
            ),
          ),
        ),
      ),
      final version => throw JournalFormatException(
        'pending decision schema version $version is not upgradable by this '
        'build, which writes version $attemptSchemaVersion',
      ),
    };

/// Accepts any upgradable version and restamps it, for records whose own
/// fields did not change.
Map<String, Object?> _stampedForward(
  Map<String, Object?> json,
  String what, {
  int to = attemptSchemaVersion,
}) {
  final version = json['schema_version'];
  if (version == attemptSchemaVersion) return json;
  if (version == 1 ||
      version == 2 ||
      version == 3 ||
      version == 4 ||
      version == 5 ||
      version == 6 ||
      version == 7 ||
      version == 8) {
    return Map<String, Object?>.of(json)..['schema_version'] = to;
  }
  throw JournalFormatException(
    '$what schema version $version is not upgradable by this build, which '
    'writes version $attemptSchemaVersion',
  );
}

/// Version 1 recorded an outcome and its derived evidence directly, because an
/// attempt could only end one way: the learner ended the presented attempt and
/// then said what happened, and nothing else could append a record. So the
/// termination is not a default chosen for convenience, it is the only thing
/// those records could have meant, and the measurement they carry is exactly
/// what they always carried.
Map<String, Object?> _version1To2(Map<String, Object?> json) {
  final upgraded = Map<String, Object?>.of(json)
    ..remove('outcome')
    ..remove('evidence_weights')
    ..remove('memory_update');

  upgraded['schema_version'] = 2;
  upgraded['closure'] = {
    'termination': AttemptTermination.learnerStopped.id,
    'measurement': {
      'status': 'MEASURED',
      'outcome': json['outcome'],
      'evidence_weights': json['evidence_weights'],
      'memory_update': json['memory_update'],
    },
  };
  return upgraded;
}

/// Version 2 recorded challenge prediction before bilateral coordination
/// participated in it. A coordination probability of one preserves that exact
/// historical meaning: overall probability remains availability times motor
/// execution.
Map<String, Object?> _version2To3(Map<String, Object?> json) {
  final upgraded = Map<String, Object?>.of(json)..['schema_version'] = 3;
  final decision = json['decision'];
  if (decision is! Map<String, Object?>) return upgraded;
  final prediction = decision['prediction'];
  if (prediction is! Map<String, Object?>) return upgraded;

  upgraded['decision'] = Map<String, Object?>.of(decision)
    ..['prediction'] = (Map<String, Object?>.of(prediction)
      ..['coordination_p'] = 1.0);
  return upgraded;
}

/// Version 3 stored opportunity kinds but not their event locations. Keeping
/// the sites empty preserves that known structure without inventing evidence.
Map<String, Object?> _version3To4(Map<String, Object?> json) {
  final upgraded = Map<String, Object?>.of(json)..['schema_version'] = 4;
  final exercise = json['exercise'];
  if (exercise is Map<String, Object?>) {
    upgraded['exercise'] = Map<String, Object?>.of(exercise)
      ..['opportunity_sites'] = <Object?>[];
  }
  return upgraded;
}

/// Version 4 recorded no presentation at all. It stays absent, which is what
/// those records can honestly say: the conditions they ran under were never
/// written down, and deriving them from a policy that has since moved would
/// assert an exposure nobody observed.
Map<String, Object?> _version4To5(Map<String, Object?> json) =>
    Map<String, Object?>.of(json)..['schema_version'] = 5;

/// Version 5 recorded no scope, timing, or input. All stay absent: the goal
/// and focus in force were never written down, the profile's goal today is not
/// evidence of the one a past decision was made under, and the transcript and
/// input the rest would be read from are gone.
Map<String, Object?> _version5To6(Map<String, Object?> json) =>
    Map<String, Object?>.of(json)..['schema_version'] = 6;

/// Version 6 could not record a pulse continuing past the count-in, and
/// practice never asked for one, so every outcome it wrote tested the learner
/// keeping the pulse alone. Both facts are written out rather than left to a
/// reader's default.
Map<String, Object?> _version6To7(Map<String, Object?> json) {
  final upgraded = Map<String, Object?>.of(json)..['schema_version'] = 7;
  if (json['presentation'] case final Map<String, Object?> presentation) {
    upgraded['presentation'] = presentationBeforeContinuingPulse(presentation);
  }
  if (json['closure'] case final Map<String, Object?> closure) {
    if (closure['measurement'] case final Map<String, Object?> measurement) {
      if (measurement['outcome'] case final Map<String, Object?> outcome) {
        upgraded['closure'] = {
          ...closure,
          'measurement': {
            ...measurement,
            'outcome': {...outcome, 'pulse_maintenance_tested': true},
          },
        };
      }
    }
  }
  return upgraded;
}

/// Version 7 could not record a beat shown on screen, and no build before it
/// showed one.
Map<String, Object?> _version7To8(Map<String, Object?> json) {
  final upgraded = Map<String, Object?>.of(json)..['schema_version'] = 8;
  if (json['presentation'] case final Map<String, Object?> presentation) {
    upgraded['presentation'] = presentationBeforeShownPulse(presentation);
  }
  return upgraded;
}

/// Version 8 did not write the rank key's contrary coordination, target shape,
/// frontier advance, or target-shaped goal flags. They read back false because
/// their values were not recorded, not because they were false.
Map<String, Object?> _version8To9(Map<String, Object?> json) {
  final upgraded = Map<String, Object?>.of(json)..['schema_version'] = 9;
  if (json['decision'] case final Map<String, Object?> decision) {
    if (decision['rank_key'] case final Map<String, Object?> rankKey) {
      upgraded['decision'] = {
        ...decision,
        'rank_key': {
          ...rankKey,
          'contrary_coordination': false,
          'target_shaped': false,
          'advances_frontier': false,
          'target_shaped_goal': false,
        },
      };
    }
  }
  return upgraded;
}

/// [presentation] as written before a continuing beat could be shown on
/// screen, in the shape that says none was.
Map<String, Object?> presentationBeforeShownPulse(
  Map<String, Object?> presentation,
) {
  if (presentation['delivery'] case final Map<String, Object?> delivery) {
    return {
      ...presentation,
      'delivery': {...delivery, 'shown_continuing_beats': 0},
    };
  }
  return presentation;
}

/// [presentation] as written before a pulse could continue past the count-in,
/// in the shape that says none did.
///
/// Every beat such a record asked for counted in, which its own conditions
/// confirm. One whose conditions asked for a metronome is refused rather than
/// split: its beats cannot be divided after the fact, and counting them all as
/// a count-in would record a pulse the learner was given as one they held.
///
/// Throws [JournalFormatException] for a presentation that asked for a
/// metronome.
Map<String, Object?> presentationBeforeContinuingPulse(
  Map<String, Object?> presentation, {
  String? location,
}) {
  if (presentation['conditions'] case {
    'tempo_support': 'METRONOME_THROUGHOUT',
  }) {
    throw JournalFormatException(
      'a presentation written before continuing pulses were recorded asked for '
      'a metronome, so its beats cannot be split around the count-in',
      location: location,
    );
  }
  if (presentation['delivery'] case final Map<String, Object?> delivery) {
    if (delivery['tempo'] case final Map<String, Object?> tempo) {
      return {
        ...presentation,
        'delivery': {
          ...delivery,
          'tempo': {
            'delivery': tempo['delivery'],
            'count_in': {
              'requested': tempo['requested_beats'],
              'delivered': tempo['delivered_beats'],
            },
            'continuing': {'requested': 0, 'delivered': 0},
            'failure_reason': tempo['failure_reason'],
          },
        },
      };
    }
  }
  return presentation;
}
