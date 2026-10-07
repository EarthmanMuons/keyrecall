import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/practice/attempt_ownership.dart';

void main() {
  test('a new claim revokes the previous owner, once', () {
    final ownership = AttemptOwnership();
    final revoked = <String>[];
    ownership.claim('a', onRevoked: () => revoked.add('a'));
    ownership.claim('b', onRevoked: () => revoked.add('b'));

    expect(revoked, ['a']);
    expect(ownership.owns('a'), isFalse);
    expect(ownership.owns('b'), isTrue);
  });

  test('a superseded owner cannot release what it lost', () {
    final ownership = AttemptOwnership()
      ..claim('a')
      ..claim('b');

    expect(ownership.release('a'), isFalse);
    expect(ownership.owns('b'), isTrue);
    expect(ownership.release('b'), isTrue);
  });

  test('claiming after a release revokes nobody', () {
    final revoked = <String>[];
    final ownership = AttemptOwnership()
      ..claim('a', onRevoked: () => revoked.add('a'));
    ownership.release('a');
    ownership.claim('b');

    expect(revoked, isEmpty);
  });
}
