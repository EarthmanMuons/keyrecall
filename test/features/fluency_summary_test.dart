import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/fluency/fluency_summary.dart';

final _cMajor = ScaleMaterial('C', ScaleForm.major);
final _gMajor = ScaleMaterial('G', ScaleForm.major);

void main() {
  group('key sectors', () {
    final sectors = keySectors(allScales);

    test('run around the circle of fifths from C', () {
      expect(
        [for (final sector in sectors) sector.pitchClass],
        [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5],
      );
      expect(sectors.every((sector) => sector.forms.length == 4), isTrue);
    });

    test('name a key the way its major and minor scales spell it', () {
      expect(sectors[0].majorTonic, 'C');
      expect(sectors[0].minorTonic, isNull);
      expect(sectors[7].majorTonic, 'Db');
      expect(sectors[7].minorTonic, 'C#');
      expect(sectors[8].majorTonic, 'Ab');
      expect(sectors[8].minorTonic, 'G#');
    });

    test('keep their shape for a narrower catalog', () {
      final narrow = keySectors([_cMajor, ...allRootPositionArpeggios]);

      expect(narrow, hasLength(12));
      expect(narrow[0].forms, {ScaleForm.major: _cMajor});
      expect(narrow.skip(1).every((sector) => sector.forms.isEmpty), isTrue);
    });

    test('refuse one form of one key spelled two ways', () {
      expect(
        () => keySectors([
          ScaleMaterial('Db', ScaleForm.major),
          ScaleMaterial('C#', ScaleForm.major),
        ]),
        throwsStateError,
      );
    });
  });

  group('a material summary', () {
    test('carries the strongest demonstration across days', () {
      final summary = FluencySummary.of(
        [
          _day(
            1,
            demonstrations: [_shown(_cMajor, DemonstrationLevel.fromMemory, 1)],
          ),
          _day(
            2,
            demonstrations: [
              _shown(_cMajor, DemonstrationLevel.notesPreviewed, 2),
              _shown(_gMajor, DemonstrationLevel.cued, 2),
            ],
          ),
        ],
        catalog: [_cMajor, _gMajor],
      );

      expect(summary[_cMajor].level, DemonstrationLevel.fromMemory);
      expect(summary[_cMajor].demonstration!.lastAt, _at(1));
      expect(summary[_gMajor].level, DemonstrationLevel.cued);
      expect(
        summary.countAt(DemonstrationLevel.fromMemory, [_cMajor, _gMajor]),
        1,
      );
    });

    test('names nothing demonstrated for a material never played', () {
      final summary = FluencySummary.of(const [], catalog: [_cMajor]);

      expect(summary[_cMajor].level, isNull);
      expect(summary[_cMajor].tempoFor(HandConfiguration.right), isNull);
    });

    test('refuses a material outside its catalog', () {
      final summary = FluencySummary.of(const [], catalog: [_cMajor]);

      expect(() => summary[_gMajor], throwsArgumentError);
    });

    test('reads tempo from the most independent rung, even if slower', () {
      final summary = FluencySummary.of(
        [
          _day(
            1,
            tempos: [
              _played(_cMajor, rung: 1, tempoBpm: 100),
              _played(_cMajor, rung: 2, tempoBpm: 80),
              _played(
                _cMajor,
                rung: 0,
                tempoBpm: 120,
                hands: HandConfiguration.left,
              ),
            ],
          ),
        ],
        catalog: [_cMajor],
      );
      final fluency = summary[_cMajor];

      expect(fluency.tempoFor(HandConfiguration.right), (
        tempoBpm: 80,
        guidanceIndependence: 2,
      ));
      expect(fluency.unguidedTempo(HandConfiguration.right), 80);
      expect(fluency.tempoFor(HandConfiguration.left), (
        tempoBpm: 120,
        guidanceIndependence: 0,
      ));
      expect(fluency.unguidedTempo(HandConfiguration.left), isNull);
    });

    test('shows only tempos that qualify', () {
      final summary = FluencySummary.of(
        [
          _day(
            1,
            tempos: [_played(_cMajor, rung: 2, tempoBpm: 90, motorScore: 0.3)],
          ),
        ],
        catalog: [_cMajor],
      );

      expect(summary[_cMajor].tempoFor(HandConfiguration.right), isNull);
    });
  });

  test('tempo bands split at 72 and 100', () {
    expect(TempoBand.of(null), TempoBand.none);
    expect(TempoBand.of(60), TempoBand.under72);
    expect(TempoBand.of(71.9), TempoBand.under72);
    expect(TempoBand.of(72), TempoBand.from72);
    expect(TempoBand.of(99.9), TempoBand.from72);
    expect(TempoBand.of(100), TempoBand.from100);
  });

  group('copy', () {
    test('a date carries its year only when it is not this one', () {
      final now = DateTime(2026, 9, 17);

      expect(demonstratedOn(DateTime(2026, 9, 8, 12), now: now), 'Sep 8');
      expect(
        demonstratedOn(DateTime(2025, 12, 30, 12), now: now),
        'Dec 30, 2025',
      );
    });

    test('a tempo names the support it was shown with', () {
      expect(rungTempoName((tempoBpm: 96.4, guidanceIndependence: 2)), '96');
      expect(
        rungTempoName((tempoBpm: 88, guidanceIndependence: 1)),
        '88 previewed',
      );
      expect(
        rungTempoName((tempoBpm: 72, guidanceIndependence: 0)),
        '72 with cues',
      );
    });
  });

  group('the wheel', () {
    const geometry = KeyWheelGeometry();

    ({double x, double y}) point(double degrees, double radius) => (
      x: radius * math.sin(degrees * math.pi / 180),
      y: -radius * math.cos(degrees * math.pi / 180),
    );

    WheelCell? at(double degrees, double radius) {
      final p = point(degrees, radius);
      return geometry.cellAt(p.x, p.y);
    }

    test('places major outermost and melodic minor innermost', () {
      final (majorOuter, _) = geometry.ringOf(ScaleForm.major);
      final (_, melodicInner) = geometry.ringOf(ScaleForm.melodicMinor);

      expect(at(0, majorOuter - 0.01), (sector: 0, form: ScaleForm.major));
      expect(at(0, melodicInner + 0.01), (
        sector: 0,
        form: ScaleForm.melodicMinor,
      ));
    });

    test('finds a sector by its angle clockwise from the top', () {
      expect(at(90, 0.7)?.sector, 3);
      expect(at(14, 0.7)?.sector, 0);
      expect(at(16, 0.7)?.sector, 1);
      expect(at(346, 0.7)?.sector, 0);
      expect(at(344, 0.7)?.sector, 11);
    });

    test('has nothing outside the rings or in the middle', () {
      expect(at(0, 0), isNull);
      expect(at(0, KeyWheelGeometry.innerRadius - 0.01), isNull);
      expect(at(0, KeyWheelGeometry.outerRadius + 0.01), isNull);
    });
  });
}

DateTime _at(int day) => DateTime.utc(2026, 1, day, 18);

FluencyDay _day(
  int day, {
  List<Demonstration> demonstrations = const [],
  List<TempoObservation> tempos = const [],
}) => FluencyDay(
  day: CalendarDay(2026, 1, day),
  attempts: demonstrations.length + tempos.length,
  demonstrations: {
    for (final demonstration in demonstrations)
      demonstration.materialId: demonstration,
  },
  tempos: tempos,
);

Demonstration _shown(
  ScaleMaterial material,
  DemonstrationLevel level,
  int day,
) => Demonstration(
  materialId: material.materialId,
  level: level,
  lastAt: _at(day),
);

TempoObservation _played(
  ScaleMaterial material, {
  required int rung,
  required double tempoBpm,
  HandConfiguration hands = HandConfiguration.right,
  double motorScore = 0.9,
}) => TempoObservation(
  materialId: material.materialId,
  hands: hands,
  handMotion: HandMotion.parallel,
  octaves: 1,
  guidanceIndependence: rung,
  requestedTempoBpm: tempoBpm,
  tempoRatio: 1,
  motorScore: motorScore,
  occurredAt: _at(1),
);
