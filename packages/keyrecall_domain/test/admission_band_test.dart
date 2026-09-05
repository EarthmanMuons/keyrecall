import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

AdmissionBand bandOf(String tonic, ArpeggioQuality quality) =>
    admissionBandOf(ArpeggioMaterial(tonic, quality));

void main() {
  group('where an arpeggio starts', () {
    test('a triad of white keys is foundation material', () {
      for (final material in [
        ArpeggioMaterial('C', ArpeggioQuality.major),
        ArpeggioMaterial('G', ArpeggioQuality.major),
        ArpeggioMaterial('F', ArpeggioQuality.major),
        ArpeggioMaterial('A', ArpeggioQuality.minor),
        ArpeggioMaterial('D', ArpeggioQuality.minor),
        ArpeggioMaterial('E', ArpeggioQuality.minor),
      ]) {
        expect(
          admissionBandOf(material),
          AdmissionBand.foundation,
          reason: '${material.materialId} is played thumb on a white root',
        );
      }
    });

    test('a black key inside a white-rooted shape comes next', () {
      expect(bandOf('D', ArpeggioQuality.major), AdmissionBand.earlyTransfer);
      expect(bandOf('E', ArpeggioQuality.major), AdmissionBand.earlyTransfer);
      expect(bandOf('B', ArpeggioQuality.minor), AdmissionBand.earlyTransfer);
    });

    test('a black root is a later band than any white-rooted shape', () {
      for (final material in [
        ArpeggioMaterial('Db', ArpeggioQuality.major),
        ArpeggioMaterial('Eb', ArpeggioQuality.major),
        ArpeggioMaterial('C#', ArpeggioQuality.minor),
        ArpeggioMaterial('G#', ArpeggioQuality.minor),
      ]) {
        expect(
          admissionBandOf(
            material,
          ).isAtLeastAsEarlyAs(AdmissionBand.earlyTransfer),
          isFalse,
          reason:
              '${material.materialId} must not compete with white-rooted '
              'shapes at a beginner frontier',
        );
      }
    });

    test('an all-black triad is the latest band there is', () {
      expect(
        bandOf('F#', ArpeggioQuality.major),
        AdmissionBand.advancedKeyboard,
      );
    });

    test('no arpeggio outside the white-key triads is foundation', () {
      for (final material in allRootPositionArpeggios) {
        if (admissionBandOf(material) != AdmissionBand.foundation) continue;
        expect(
          material.tonic,
          isIn(const ['C', 'G', 'F', 'A', 'D', 'E']),
          reason: 'a beginner meets a small, structurally simple subset first',
        );
      }
    });
  });
}
