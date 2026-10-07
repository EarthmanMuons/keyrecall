import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/practice/goal_progress.dart';

void main() {
  ActiveFocus focus(FocusStrength strength) => ActiveFocus(
    material: MaterialFocus(familyIds: {TechnicalMaterial.scaleFamilyId}),
    strength: strength,
    label: 'Scales',
  );

  test('general technique has no finish line to count toward', () {
    expect(hasFinishLine(PracticePlan.normal), isFalse);
    expect(
      hasFinishLine(
        PracticePlan.normal.focusedOn(focus(FocusStrength.emphasis)),
      ),
      isFalse,
      reason: 'an emphasis narrows nothing',
    );
  });

  test('a chosen set does', () {
    expect(
      hasFinishLine(
        PracticePlan.normal.focusedOn(focus(FocusStrength.exclusive)),
      ),
      isTrue,
    );
    expect(hasFinishLine(const PracticePlan(goalId: 'FOUNDATIONS')), isTrue);
    expect(hasFinishLine(const PracticePlan(goalId: 'KEY_FLUENCY_24')), isTrue);
  });
}
