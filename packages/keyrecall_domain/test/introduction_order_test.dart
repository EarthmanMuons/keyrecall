import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

/// Sharps as positive counts and flats as negative ones.
const Map<String, int> _majorSignatures = {
  'C': 0,
  'G': 1,
  'D': 2,
  'A': 3,
  'E': 4,
  'B': 5,
  'F#': 6,
  'F': -1,
  'Bb': -2,
  'Eb': -3,
  'Ab': -4,
  'Db': -5,
};
const Map<String, int> _minorSignatures = {
  'A': 0,
  'E': 1,
  'B': 2,
  'F#': 3,
  'C#': 4,
  'G#': 5,
  'D': -1,
  'G': -2,
  'C': -3,
  'F': -4,
  'Bb': -5,
  'Eb': -6,
};

int _signatureOf(({String tonic, bool major}) tonality) =>
    (tonality.major ? _majorSignatures : _minorSignatures)[tonality.tonic]!;

void main() {
  test('the tonalities are the catalog\'s majors and natural minors', () {
    expect(tonalitiesByKeySignature.toSet(), hasLength(24));
    expect(tonalitiesByKeySignature.toSet(), {
      for (final scale in allScales)
        if (scale.form == ScaleForm.major ||
            scale.form == ScaleForm.naturalMinor)
          (tonic: scale.tonic, major: scale.form == ScaleForm.major),
    });
  });

  test('fewest accidentals first, then major, then sharps', () {
    for (var i = 1; i < tonalitiesByKeySignature.length; i++) {
      final before = tonalitiesByKeySignature[i - 1];
      final after = tonalitiesByKeySignature[i];
      final (a, b) = (_signatureOf(before), _signatureOf(after));
      final where = '$before then $after';
      expect(a.abs(), lessThanOrEqualTo(b.abs()), reason: where);
      if (a.abs() == b.abs() && before.major == after.major) {
        expect(a, greaterThan(b), reason: 'sharps before flats: $where');
      }
      if (a.abs() == b.abs() && before.major != after.major) {
        expect(before.major, isTrue, reason: 'majors before minors: $where');
      }
    }
  });

  group('introducing the catalog', () {
    final catalog = [...allScales, ...allRootPositionArpeggios];
    final ordered = inIntroductionOrder(catalog);

    test('keeps every material once', () {
      expect(ordered, hasLength(catalog.length));
      expect(ordered.toSet(), catalog.toSet());
    });

    test('meets each key as its scale and then its arpeggio', () {
      expect(ordered.take(6).map((m) => m.materialId), [
        'C_MAJOR',
        'C_MAJOR_ROOT_ARPEGGIO',
        'A_NATURAL_MINOR',
        'A_MINOR_ROOT_ARPEGGIO',
        'G_MAJOR',
        'G_MAJOR_ROOT_ARPEGGIO',
      ]);
    });

    test('extends the minors only after every key is met', () {
      final forms = [
        for (final material in ordered)
          if (material case ScaleMaterial(:final form)) form,
      ];
      final firstAltered = forms.indexWhere(
        (form) =>
            form == ScaleForm.harmonicMinor || form == ScaleForm.melodicMinor,
      );
      expect(forms.take(firstAltered).toSet(), {
        ScaleForm.major,
        ScaleForm.naturalMinor,
      });
      final altered = forms.skip(firstAltered).toList();
      expect(altered.take(12), everyElement(ScaleForm.harmonicMinor));
      expect(altered.skip(12), everyElement(ScaleForm.melodicMinor));
      expect(
        [
          for (final material in ordered)
            if (material case ScaleMaterial(
              form: ScaleForm.harmonicMinor,
              :final tonic,
            ))
              tonic,
        ],
        [
          for (final tonality in tonalitiesByKeySignature)
            if (!tonality.major) tonality.tonic,
        ],
      );
    });

    test('keeps anything it has no place for after, in its given order', () {
      final inversion = ArpeggioMaterial(
        'C',
        ArpeggioQuality.major,
        inversion: ArpeggioInversion.first,
      );
      final placed = inIntroductionOrder([
        inversion,
        ScaleMaterial('G', ScaleForm.major),
        ScaleMaterial('C', ScaleForm.major),
      ]);

      expect(placed.map((m) => m.materialId), [
        'C_MAJOR',
        'G_MAJOR',
        inversion.materialId,
      ]);
    });
  });
}
