import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  const keyboardCountIn = PresentationConditions(
    pitchRepresentation: PitchRepresentation.keyboard,
    tempoSupport: TempoSupport.countInOnly,
  );
  const nothingCountIn = PresentationConditions(
    pitchRepresentation: PitchRepresentation.none,
    tempoSupport: TempoSupport.countInOnly,
  );

  group('pairing with guidance', () {
    test('both supported rungs need something to show', () {
      for (final guidance in [
        GuidanceContext.continuouslyCued,
        GuidanceContext.notesPreviewedOnly,
      ]) {
        expect(keyboardCountIn.suitsGuidance(guidance), isTrue);
        expect(
          nothingCountIn.suitsGuidance(guidance),
          isFalse,
          reason:
              'a rung that supplies material must have a representation, '
              'whether it shows it throughout or only before the attempt',
        );
      }
    });

    test('an unguided attempt must present no pitch material', () {
      expect(nothingCountIn.suitsGuidance(GuidanceContext.unguided), isTrue);
      expect(keyboardCountIn.suitsGuidance(GuidanceContext.unguided), isFalse);
    });

    test('tempo support is free of the guidance rung', () {
      for (final tempo in TempoSupport.values) {
        expect(
          PresentationConditions(
            pitchRepresentation: PitchRepresentation.none,
            tempoSupport: tempo,
          ).suitsGuidance(GuidanceContext.unguided),
          isTrue,
          reason:
              'tempo support is a separate axis: no value of it makes a '
              'presentation illegal under a guidance rung',
        );
      }
    });
  });

  group('representation', () {
    test('separates supplying material from demanding decoding', () {
      expect(PitchRepresentation.keyboard.suppliesPitchMaterial, isTrue);
      expect(PitchRepresentation.keyboard.demandsNotationDecoding, isFalse);
      expect(PitchRepresentation.staff.suppliesPitchMaterial, isTrue);
      expect(PitchRepresentation.staff.demandsNotationDecoding, isTrue);
      expect(PitchRepresentation.none.suppliesPitchMaterial, isFalse);
      expect(
        PitchRepresentation.none.demandsNotationDecoding,
        isFalse,
        reason:
            'showing no notation is not a reading task, and must not be '
            'read as a harder one',
      );
    });
  });

  test('value equality, so a presentation can be compared and stored', () {
    expect(
      keyboardCountIn,
      const PresentationConditions(
        pitchRepresentation: PitchRepresentation.keyboard,
        tempoSupport: TempoSupport.countInOnly,
      ),
    );
    expect(keyboardCountIn, isNot(nothingCountIn));
  });
}
