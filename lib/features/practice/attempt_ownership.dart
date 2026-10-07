import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which attempt view the shared attempt resources answer to: the screen wake
/// lock and the pulse's audio engine.
///
/// A view leaving the screen can outlive the one replacing it by a
/// transition, so only the view that still owns them may switch them off. One
/// that has been superseded detaches without touching what its successor set
/// up.
class AttemptOwnership {
  Object? _owner;

  void claim(Object owner) => _owner = owner;

  bool owns(Object owner) => identical(_owner, owner);

  /// Gives the resources up, answering whether [owner] had them to give.
  bool release(Object owner) {
    if (!owns(owner)) return false;
    _owner = null;
    return true;
  }
}

final attemptOwnershipProvider = Provider<AttemptOwnership>(
  (ref) => AttemptOwnership(),
);
