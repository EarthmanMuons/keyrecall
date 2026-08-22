/// Rejects an attempt to move [subject] backward in time.
///
/// State transitions are only defined forward. Propagating to an earlier
/// instant and later returning would diffuse, revert, or decay the same
/// interval twice, and an attempt applied out of order would fold evidence
/// into a state that had already moved past it. Both corrupt replay quietly,
/// so both fail loudly instead.
///
/// Throws [ArgumentError] when [now] is before [reached].
void requireForwardPropagation(DateTime now, DateTime reached, String subject) {
  if (now.isBefore(reached)) {
    throw ArgumentError.value(
      now,
      'now',
      'time cannot move backward: $subject has already reached '
          '${reached.toIso8601String()}',
    );
  }
}
