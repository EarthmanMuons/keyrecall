import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which attempt view the shared attempt resources answer to: the screen wake
/// lock and the pulse's audio engine.
///
/// A view leaving the screen can outlive the one replacing it by a
/// transition, so only the view that still owns them may start anything on
/// them or switch them off. One that has been superseded is told at once, so
/// it can stop what it had scheduled, and then detaches without touching what
/// its successor set up.
class AttemptOwnership {
  Object? _owner;
  void Function()? _onRevoked;

  /// Takes the resources for [owner], revoking them from whoever had them.
  void claim(Object owner, {void Function()? onRevoked}) {
    final previous = _owner;
    final revoke = _onRevoked;
    _owner = owner;
    _onRevoked = onRevoked;
    if (previous != null && !identical(previous, owner)) revoke?.call();
  }

  bool owns(Object owner) => identical(_owner, owner);

  /// Gives the resources up, answering whether [owner] had them to give.
  bool release(Object owner) {
    if (!owns(owner)) return false;
    _owner = null;
    _onRevoked = null;
    return true;
  }
}

final attemptOwnershipProvider = Provider<AttemptOwnership>(
  (ref) => AttemptOwnership(),
);
