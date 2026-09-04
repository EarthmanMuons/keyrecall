import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'package:keyrecall/features/practice/profile_color.dart';

void main() {
  Profile profileNamed(String name, {String? id, String? hint}) => Profile(
    id: id ?? name.toLowerCase(),
    displayName: name,
    createdAt: DateTime.utc(2026),
    placement: PlacementTier.someExperience,
    presentationHint: hint,
  );

  test('a recorded color is the one shown', () {
    expect(
      ProfileColor.of(profileNamed('Alice', hint: ProfileColor.teal.name)),
      ProfileColor.teal,
    );
  });

  test('a profile recorded before colors gets a stable one anyway', () {
    final profile = profileNamed('Alice');

    expect(ProfileColor.of(profile), ProfileColor.of(profile));
  });

  test('an unreadable hint falls back rather than failing', () {
    expect(
      ProfileColor.of(profileNamed('Alice', hint: 'chartreuse')),
      isA<ProfileColor>(),
    );
  });

  test('a new profile does not take a color already in use', () {
    final here = [
      profileNamed('Alice', hint: ProfileColor.amber.name),
      profileNamed('Bob', hint: ProfileColor.teal.name),
    ];

    final next = ProfileColor.unusedAmong(here);

    expect(next, isNot(ProfileColor.amber));
    expect(next, isNot(ProfileColor.teal));
  });

  test('more people than colors wraps rather than refusing', () {
    final crowd = [
      for (final color in ProfileColor.values)
        profileNamed(color.name, id: color.name, hint: color.name),
    ];

    expect(ProfileColor.unusedAmong(crowd), isA<ProfileColor>());
  });
}
