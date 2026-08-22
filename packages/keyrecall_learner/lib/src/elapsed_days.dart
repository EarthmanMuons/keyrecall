/// Elapsed-time helpers for the day-based learner mathematics.
///
/// Half-lives, diffusion rates, and reversion time constants are all
/// expressed in days, while state timestamps are UTC [DateTime] values.
/// These conversions are the only place the two meet.
extension ElapsedDays on DateTime {
  /// Days from this instant until [other]; negative when [other] is earlier.
  double daysUntil(DateTime other) =>
      other.difference(this).inMicroseconds / Duration.microsecondsPerDay;

  /// This instant advanced by a fractional number of [days].
  ///
  /// Rounds to the platform's timestamp resolution, which is microseconds on
  /// native targets and milliseconds on the web.
  DateTime plusDays(double days) =>
      add(Duration(microseconds: (days * Duration.microsecondsPerDay).round()));
}
