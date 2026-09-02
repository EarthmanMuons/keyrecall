import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:meta/meta.dart';

enum PostAttemptFeedback {
  /// No measured performance feedback was shown.
  none('NONE'),

  /// Aggregate performance measurements only.
  summary('SUMMARY'),

  /// Names or interprets a performance fault; a summary may accompany it.
  diagnostic('DIAGNOSTIC');

  const PostAttemptFeedback(this.id);

  final String id;

  static PostAttemptFeedback fromId(String id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () =>
        throw JournalFormatException('unknown post-attempt feedback "$id"'),
  );
}

enum ProgressFeedback {
  none('NONE'),
  personalProgress('PERSONAL_PROGRESS');

  const ProgressFeedback(this.id);

  final String id;

  static ProgressFeedback fromId(String id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () =>
        throw JournalFormatException('unknown progress feedback "$id"'),
  );
}

enum ProgressEventKind {
  firstCleanCompletion('FIRST_CLEAN_COMPLETION'),
  firstIndependentCompletion('FIRST_INDEPENDENT_COMPLETION'),
  repeatedReliability('REPEATED_RELIABILITY');

  const ProgressEventKind(this.id);

  final String id;

  static ProgressEventKind fromId(String id) => values.firstWhere(
    (value) => value.id == id,
    orElse: () => throw JournalFormatException('unknown progress event "$id"'),
  );
}

@immutable
class FeedbackExposure {
  final String profileId;
  final String attemptId;
  final DateTime shownAt;
  final PostAttemptFeedback postAttemptFeedback;
  final ProgressFeedback progressFeedback;
  final List<ProgressEventKind> progressEvents;

  FeedbackExposure({
    required String profileId,
    required this.attemptId,
    required DateTime shownAt,
    required this.postAttemptFeedback,
    required this.progressFeedback,
    required Iterable<ProgressEventKind> progressEvents,
  }) : profileId = requireProfileId(profileId),
       shownAt = shownAt.toUtc(),
       progressEvents = List.unmodifiable(progressEvents) {
    if (attemptId.isEmpty) {
      throw ArgumentError.value(attemptId, 'attemptId');
    }
    if (this.progressEvents.isNotEmpty !=
        (progressFeedback == ProgressFeedback.personalProgress)) {
      throw ArgumentError(
        'progress events are required exactly when progress was shown',
      );
    }
    if (this.progressEvents.toSet().length != this.progressEvents.length) {
      throw ArgumentError.value(progressEvents, 'progressEvents');
    }
  }

  Map<String, Object?> toJson() => {
    'profile_id': profileId,
    'attempt_id': attemptId,
    'shown_at': encodeTime(shownAt),
    'post_attempt_feedback': postAttemptFeedback.id,
    'progress_feedback': progressFeedback.id,
    'progress_events': progressEvents.map((event) => event.id).toList(),
  };

  factory FeedbackExposure.fromJson(Map<String, Object?> json) =>
      FeedbackExposure(
        profileId: requireString(json, 'profile_id'),
        attemptId: requireString(json, 'attempt_id'),
        shownAt: requireTime(json, 'shown_at'),
        postAttemptFeedback: PostAttemptFeedback.fromId(
          requireString(json, 'post_attempt_feedback'),
        ),
        progressFeedback: ProgressFeedback.fromId(
          requireString(json, 'progress_feedback'),
        ),
        progressEvents: _decodeProgressEvents(json),
      );

  @override
  bool operator ==(Object other) =>
      other is FeedbackExposure &&
      other.profileId == profileId &&
      other.attemptId == attemptId &&
      other.shownAt == shownAt &&
      other.postAttemptFeedback == postAttemptFeedback &&
      other.progressFeedback == progressFeedback &&
      _sameEvents(other.progressEvents, progressEvents);

  @override
  int get hashCode => Object.hash(
    profileId,
    attemptId,
    shownAt,
    postAttemptFeedback,
    progressFeedback,
    Object.hashAll(progressEvents),
  );
}

List<ProgressEventKind> _decodeProgressEvents(Map<String, Object?> json) {
  if (json.containsKey('progress_events')) {
    final events = json['progress_events'];
    if (events is! List<Object?>) {
      throw const JournalFormatException('progress_events must be a list');
    }
    return [
      for (final event in events)
        if (event is String)
          ProgressEventKind.fromId(event)
        else
          throw const JournalFormatException(
            'progress_events must contain strings',
          ),
    ];
  }
  return switch (json['progress_event']) {
    final String id => [ProgressEventKind.fromId(id)],
    null => const [],
    _ => throw const JournalFormatException(
      'progress_event must be a string or null',
    ),
  };
}

bool _sameEvents(List<ProgressEventKind> a, List<ProgressEventKind> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
