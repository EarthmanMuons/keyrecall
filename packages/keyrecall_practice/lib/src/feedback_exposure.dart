import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:meta/meta.dart';

enum PostAttemptFeedback {
  none('NONE'),
  summary('SUMMARY'),
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
  final ProgressEventKind? progressEvent;

  FeedbackExposure({
    required String profileId,
    required this.attemptId,
    required DateTime shownAt,
    required this.postAttemptFeedback,
    required this.progressFeedback,
    this.progressEvent,
  }) : profileId = requireProfileId(profileId),
       shownAt = shownAt.toUtc() {
    if (attemptId.isEmpty) {
      throw ArgumentError.value(attemptId, 'attemptId');
    }
    if ((progressEvent != null) !=
        (progressFeedback == ProgressFeedback.personalProgress)) {
      throw ArgumentError(
        'a progress event is required exactly when progress was shown',
      );
    }
  }

  Map<String, Object?> toJson() => {
    'profile_id': profileId,
    'attempt_id': attemptId,
    'shown_at': encodeTime(shownAt),
    'post_attempt_feedback': postAttemptFeedback.id,
    'progress_feedback': progressFeedback.id,
    'progress_event': progressEvent?.id,
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
        progressEvent: switch (json['progress_event']) {
          final String id => ProgressEventKind.fromId(id),
          null => null,
          _ => throw const JournalFormatException(
            'progress_event must be a string or null',
          ),
        },
      );

  @override
  bool operator ==(Object other) =>
      other is FeedbackExposure &&
      other.profileId == profileId &&
      other.attemptId == attemptId &&
      other.shownAt == shownAt &&
      other.postAttemptFeedback == postAttemptFeedback &&
      other.progressFeedback == progressFeedback &&
      other.progressEvent == progressEvent;

  @override
  int get hashCode => Object.hash(
    profileId,
    attemptId,
    shownAt,
    postAttemptFeedback,
    progressFeedback,
    progressEvent,
  );
}
