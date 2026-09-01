import 'dart:async';

/// Runs work for one profile at a time, in the order it arrived.
///
/// Store operations read, decide, and then write, with suspension points in
/// between. Two of them running against one profile can interleave at those
/// points, and the second read then reflects a state the first has already
/// decided to replace.
///
/// Per profile rather than globally, because histories share nothing.
class ProfileWriteQueue {
  final Map<String, Future<void>> _tails = {};

  /// Runs [operation] once everything already queued for [profileId] is done.
  Future<T> run<T>(String profileId, Future<T> Function() operation) {
    final waitFor = _tails[profileId];
    final done = Completer<void>();
    _tails[profileId] = done.future;

    final result = waitFor == null
        ? operation()
        : waitFor.then((_) => operation());

    return result.whenComplete(() {
      // The tail is only this operation's while nothing queued behind it.
      _tails.removeWhere(
        (key, tail) => key == profileId && identical(tail, done.future),
      );
      done.complete();
    });
  }
}
