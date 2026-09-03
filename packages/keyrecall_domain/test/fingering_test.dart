import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  final testProvenance = FingeringProvenance(
    source: 'Test source',
    sourceEdition: '1',
    sourceLocation: 'p. 1',
    status: CanonicalFingeringStatus.established,
  );

  test('a fingering does not retain mutable caller lists', () {
    final entry = [1];
    final cycle = [2, 3, 1];
    final fingering = CanonicalFingering(
      materialId: 'TEST_MATERIAL',
      hand: Hand.right,
      entry: entry,
      cycle: cycle,
      reversesForDescending: true,
      provenance: testProvenance,
    );

    entry[0] = 5;
    cycle.add(4);

    expect(fingering.entry, [1]);
    expect(fingering.cycle, [2, 3, 1]);
  });

  test('a canonical record carries identity and provenance', () {
    final fingering = canonicalFingering(
      ArpeggioMaterial('D', ArpeggioQuality.major),
      Hand.left,
    )!;

    expect(fingering.materialId, 'D_MAJOR_ROOT_ARPEGGIO');
    expect(fingering.hand, Hand.left);
    expect(fingering.provenance.source, 'Michael Clark, Piano Basics');
    expect(fingering.provenance.sourceEdition, '2026');
    expect(fingering.provenance.status, CanonicalFingeringStatus.established);
  });

  test('descent exists only when the record establishes reversal', () {
    final unsupported = CanonicalFingering(
      materialId: 'TEST_MATERIAL',
      hand: Hand.right,
      entry: [1],
      cycle: [2, 3, 1],
      terminalFinger: 5,
      reversesForDescending: false,
      provenance: testProvenance,
    );
    final supported = canonicalFingering(
      ArpeggioMaterial('C', ArpeggioQuality.major),
      Hand.right,
    )!;

    expect(unsupported.descending(1), isNull);
    expect(supported.descending(1), [5, 3, 2, 1]);
  });

  String digits(List<int> fingers) => fingers.join();

  Exercise scale(
    String tonic,
    ScaleForm form, {
    int octaves = 1,
    ExerciseDirection direction = ExerciseDirection.up,
    HandConfiguration hands = HandConfiguration.right,
  }) => Exercise.linear(
    material: TechnicalMaterial(tonic, form),
    hands: hands,
    octaves: octaves,
    direction: direction,
  );

  group('hands moving contrary to each other', () {
    List<int>? contraryFingers(Hand hand) => fingeringFor(
      Exercise.linear(
        material: TechnicalMaterial('C', ScaleForm.major),
        hands: HandConfiguration.together,
        octaves: 1,
        direction: ExerciseDirection.up,
        handMotion: HandMotion.contrary,
      ),
      hand,
    );

    test('the ascending hand is fingered as it always was', () {
      expect(digits(contraryFingers(Hand.right)!), '12312345');
    });

    test('the descending hand takes its pattern from the far end', () {
      // Walking down from the shared tonic, the left hand begins on the finger
      // that would have ended an ascent.
      expect(digits(contraryFingers(Hand.left)!), '12312345');
    });

    test('the hands use homologous fingers throughout', () {
      // Why contrary motion is the easier first coordination task: both thumbs
      // start together and the crossings fall in the same places, where
      // parallel motion pairs different fingers against each other.
      expect(contraryFingers(Hand.left), contraryFingers(Hand.right));
    });
  });

  group('one octave matches the catalog summaries', () {
    test('the conventional white-key hands', () {
      expect(
        digits(fingeringFor(scale('C', ScaleForm.major), Hand.right)!),
        '12312345',
      );
      expect(
        digits(
          fingeringFor(
            scale('C', ScaleForm.major, hands: HandConfiguration.left),
            Hand.left,
          )!,
        ),
        '54321321',
      );
      expect(
        digits(fingeringFor(scale('F', ScaleForm.major), Hand.right)!),
        '12341234',
      );
      expect(
        digits(
          fingeringFor(
            scale('B', ScaleForm.major, hands: HandConfiguration.left),
            Hand.left,
          )!,
        ),
        '43214321',
      );
    });

    test('the black-key hands', () {
      expect(
        digits(fingeringFor(scale('Db', ScaleForm.major), Hand.right)!),
        '23123412',
      );
      expect(
        digits(fingeringFor(scale('F#', ScaleForm.major), Hand.right)!),
        '23412312',
      );
      expect(
        digits(fingeringFor(scale('Bb', ScaleForm.major), Hand.right)!),
        '21231234',
      );
      expect(
        digits(
          fingeringFor(
            scale('Ab', ScaleForm.major, hands: HandConfiguration.left),
            Hand.left,
          )!,
        ),
        '32143213',
      );
    });

    test('the minor forms the audit corrected', () {
      // The multi-octave audit replaced the 23123123 summaries these were
      // once given.
      for (final tonic in ['C#', 'F#', 'G#']) {
        expect(
          digits(
            fingeringFor(scale(tonic, ScaleForm.harmonicMinor), Hand.right)!,
          ),
          '34123123',
          reason: '$tonic harmonic minor right hand',
        );
      }
      expect(
        digits(fingeringFor(scale('F#', ScaleForm.naturalMinor), Hand.right)!),
        '34123123',
      );
      expect(
        digits(fingeringFor(scale('G#', ScaleForm.melodicMinor), Hand.right)!),
        '34123123',
      );
    });

    test('the two melodic minors the raised sixth changes', () {
      for (final tonic in ['C#', 'F#']) {
        expect(
          digits(
            fingeringFor(scale(tonic, ScaleForm.melodicMinor), Hand.right)!,
          ),
          '23123412',
          reason: '$tonic melodic minor right hand, not the harmonic one',
        );
        expect(
          digits(
            fingeringFor(scale(tonic, ScaleForm.harmonicMinor), Hand.right)!,
          ),
          '34123123',
        );
      }
    });

    test('E flat harmonic and natural minor differ only at the entry', () {
      expect(
        digits(fingeringFor(scale('Eb', ScaleForm.naturalMinor), Hand.right)!),
        '31234123',
      );
      expect(
        digits(fingeringFor(scale('Eb', ScaleForm.harmonicMinor), Hand.right)!),
        '21234123',
      );
    });
  });

  group('more than one octave', () {
    test('continues on the internal tonic, and ends on the terminal one', () {
      expect(
        digits(
          fingeringFor(scale('C', ScaleForm.major, octaves: 2), Hand.right)!,
        ),
        '123123412312345',
        reason:
            'the internal C takes the thumb so the scale can continue; '
            'only the last one takes five',
      );
      expect(
        digits(
          fingeringFor(
            scale(
              'C',
              ScaleForm.major,
              octaves: 2,
              hands: HandConfiguration.left,
            ),
            Hand.left,
          )!,
        ),
        '543213214321321',
      );
    });

    test(
      'an internal tonic can differ from the one the traversal starts on',
      () {
        // B flat major right hand starts on the second finger and takes the
        // fourth on every B flat after that.
        expect(
          digits(
            fingeringFor(scale('Bb', ScaleForm.major, octaves: 2), Hand.right)!,
          ),
          '212312341231234',
        );
      },
    );

    test('a descent reverses the ascent', () {
      final upDown = fingeringFor(
        scale('C', ScaleForm.major, direction: ExerciseDirection.upDown),
        Hand.right,
      )!;

      expect(digits(upDown), '123123454321321');
      expect(upDown.length, 15);
    });

    test('arpeggios replace a terminal finger at internal boundaries', () {
      final c = ArpeggioMaterial('C', ArpeggioQuality.major);
      final d = ArpeggioMaterial('D', ArpeggioQuality.major);

      expect(canonicalFingering(c, Hand.right)!.ascending(1), [1, 2, 3, 5]);
      expect(canonicalFingering(c, Hand.right)!.ascending(2), [
        1,
        2,
        3,
        1,
        2,
        3,
        5,
      ]);
      expect(canonicalFingering(c, Hand.left)!.ascending(2), [
        5,
        4,
        2,
        1,
        4,
        2,
        1,
      ]);
      expect(canonicalFingering(d, Hand.left)!.ascending(2), [
        5,
        3,
        2,
        1,
        3,
        2,
        1,
      ]);
    });
  });

  group('coverage', () {
    test('every scale form in the catalog has both hands', () {
      for (final material in v1ScaleCatalog) {
        for (final hand in Hand.values) {
          expect(
            canonicalFingering(material, hand),
            isNotNull,
            reason: '${material.materialId} $hand',
          );
        }
      }
    });

    test('a fingering exists for one tonic of every form', () {
      for (final form in ScaleForm.values) {
        expect(
          canonicalFingering(TechnicalMaterial('C', form), Hand.right),
          isNotNull,
          reason: form.id,
        );
      }
    });

    test('unsupported arpeggios do not inherit a guessed fingering', () {
      final unsupported = ArpeggioMaterial('F', ArpeggioQuality.major);

      for (final hand in Hand.values) {
        expect(canonicalFingering(unsupported, hand), isNull);
      }
    });

    test('the traversal is as long as the exercise', () {
      final exercise = scale(
        'F#',
        ScaleForm.harmonicMinor,
        octaves: 2,
        direction: ExerciseDirection.upDown,
      );

      expect(
        fingeringFor(exercise, Hand.right)!.length,
        realize(exercise).moments.length,
      );
    });
  });
}
