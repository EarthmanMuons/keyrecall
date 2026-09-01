import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  test('a goal does not retain a mutable caller scope', () {
    final targetMaterialIds = {'C_MAJOR'};
    final goal = PracticeGoal(
      id: 'TEST_GOAL',
      targetMaterialIds: targetMaterialIds,
    );

    targetMaterialIds.add('G_MAJOR');

    expect(goal.targetMaterialIds, {'C_MAJOR'});
  });
}
