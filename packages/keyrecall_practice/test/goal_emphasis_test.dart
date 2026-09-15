import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

final _material = fixtureMaterials.first;

void main() {
  test('one material takes the strongest weight put on it', () {
    final emphasis = goalEmphasisOf(_scopeWeighted([0.5, 1, 2]));

    expect(emphasis.weightByMaterialId[_material.materialId], 2);
  });

  test('a de-emphasis does not answer for what something else asked for', () {
    final emphasis = goalEmphasisOf(_scopeWeighted([0.5, 1]));

    expect(
      emphasis.weightByMaterialId,
      isEmpty,
      reason: 'the strongest of the two is neutral, so nothing is overridden',
    );
  });

  test('a scope that emphasizes nothing carries no weights', () {
    expect(goalEmphasisOf(_scopeWeighted([1, 1])).isEmpty, isTrue);
  });
}

/// One requirement per weight, all over the same material.
ResolvedPracticeScope _scopeWeighted(List<double> weights) =>
    ResolvedPracticeScope(
      goalId: 'GOAL',
      curriculumId: 'CURRICULUM',
      curriculumVersion: '1',
      isNarrow: false,
      requirements: [
        for (final (index, weight) in weights.indexed)
          ResolvedRequirement(
            requirement: CurriculumRequirement(
              id: 'REQUIREMENT_$index',
              familyId: _material.familyId,
              materialId: _material.materialId,
            ),
            material: _material,
            candidates: [
              Exercise.linear(
                material: _material,
                hands: HandConfiguration.right,
              ),
            ],
            emphasis: weight,
          ),
      ],
    );
