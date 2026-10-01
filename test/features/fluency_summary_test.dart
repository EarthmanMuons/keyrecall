import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/fluency/fluency_summary.dart';
import 'package:keyrecall/features/fluency/report_groups.dart';

final _cMajor = ScaleMaterial('C', ScaleForm.major);
final _gMajor = ScaleMaterial('G', ScaleForm.major);
final _cMajorArpeggio = ArpeggioMaterial('C', ArpeggioQuality.major);
final _scaleRings = (scaleGroup.view as WheelView).rings;

void main() {
  group('key sectors', () {
    final sectors = keySectors(allScales, _scaleRings);

    test('run around the circle of fifths from C', () {
      expect(
        [for (final sector in sectors) sector.pitchClass],
        [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5],
      );
      expect(sectors.every((sector) => sector.materials.length == 4), isTrue);
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
      final narrow = keySectors([_cMajor], _scaleRings);

      expect(narrow, hasLength(12));
      expect(narrow[0].cells, [_cMajor, null, null, null]);
      expect(
        narrow.skip(1).every((sector) => sector.materials.isEmpty),
        isTrue,
      );
    });

    test("list a key's scales outermost ring first", () {
      expect(sectors[0].materials, [
        for (final form in ScaleForm.values) ScaleMaterial('C', form),
      ]);
    });

    test('refuse a material no ring holds', () {
      expect(
        () => keySectors([_cMajorArpeggio], _scaleRings),
        throwsStateError,
      );
    });

    test('refuse one form of one key spelled two ways', () {
      expect(
        () => keySectors([
          ScaleMaterial('Db', ScaleForm.major),
          ScaleMaterial('C#', ScaleForm.major),
        ], _scaleRings),
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

  group('a material detail', () {
    MaterialDetail detailOf(
      TechnicalMaterial material,
      List<TempoObservation> tempos,
    ) => MaterialDetail.of(
      FluencySummary.of(
        [_day(1, tempos: tempos)],
        catalog: [_cMajor, _cMajorArpeggio],
      )[material],
    );

    test('reads a row per hand and a column per scale span, in order', () {
      final detail = detailOf(_cMajor, [
        _played(_cMajor, rung: 2, tempoBpm: 80),
        _played(_cMajor, rung: 1, tempoBpm: 72, octaves: 2),
        _played(
          _cMajor,
          rung: 0,
          tempoBpm: 60,
          hands: HandConfiguration.together,
        ),
      ]);

      expect(detail.octaveSpans, [1, 2]);
      expect(
        [for (final row in detail.rows) row.hands],
        [
          HandConfiguration.right,
          HandConfiguration.left,
          HandConfiguration.together,
        ],
      );
      expect(
        [for (final row in detail.rows) row.tempos],
        [
          [
            (tempoBpm: 80.0, guidanceIndependence: 2),
            (tempoBpm: 72.0, guidanceIndependence: 1),
          ],
          [null, null],
          [(tempoBpm: 60.0, guidanceIndependence: 0), null],
        ],
      );
    });

    test('knows whether any cell holds a tempo', () {
      expect(detailOf(_cMajor, []).hasTempo, isFalse);
      expect(
        detailOf(_cMajor, [_played(_cMajor, rung: 1, tempoBpm: 60)]).hasTempo,
        isTrue,
      );
    });

    test('takes its spans from the progression', () {
      final detail = detailOf(_cMajorArpeggio, [
        _played(_cMajorArpeggio, rung: 2, tempoBpm: 66, octaves: 4),
      ]);

      expect(detail.octaveSpans, _cMajorArpeggio.progression.octaveSpans);
      expect(detail.octaveSpans, [1, 2, 4]);
      expect(detail.rows.first.tempos.last, (
        tempoBpm: 66.0,
        guidanceIndependence: 2,
      ));
    });

    test('holds no cell for a span the material does not offer', () {
      final detail = detailOf(_cMajor, [
        _played(_cMajor, rung: 2, tempoBpm: 80, octaves: 4),
      ]);

      expect(detail.octaveSpans, isNot(contains(4)));
      expect(detail.rows.every((row) => row.tempos.length == 2), isTrue);
      expect(
        detail.rows.expand((row) => row.tempos).every((tempo) => tempo == null),
        isTrue,
      );
    });

    test("never shows another material's tempos", () {
      final tempos = [
        _played(_cMajorArpeggio, rung: 2, tempoBpm: 120),
        _played(_cMajor, rung: 2, tempoBpm: 76),
      ];

      expect(detailOf(_cMajor, tempos).rows.first.tempos.first, (
        tempoBpm: 76.0,
        guidanceIndependence: 2,
      ));
      expect(detailOf(_cMajorArpeggio, tempos).rows.first.tempos.first, (
        tempoBpm: 120.0,
        guidanceIndependence: 2,
      ));
    });
  });

  group('the tempo lens', () {
    HandConfiguration opensOn(List<TempoObservation> tempos) => tempoLensHands(
      FluencySummary.of([_day(1, tempos: tempos)], catalog: [_cMajor, _gMajor]),
      [_cMajor, _gMajor],
    );

    test('opens on the right hand before anything is shown', () {
      expect(opensOn([]), HandConfiguration.right);
    });

    test('opens on the hand with more tempos from memory', () {
      expect(
        opensOn([
          _played(
            _cMajor,
            rung: 2,
            tempoBpm: 60,
            hands: HandConfiguration.left,
          ),
          _played(
            _gMajor,
            rung: 2,
            tempoBpm: 60,
            hands: HandConfiguration.left,
          ),
          _played(_cMajor, rung: 2, tempoBpm: 60),
        ]),
        HandConfiguration.left,
      );
    });

    test('opens on together once any tempo from memory is together', () {
      expect(
        opensOn([
          _played(_cMajor, rung: 2, tempoBpm: 80),
          _played(_gMajor, rung: 2, tempoBpm: 80),
          _played(
            _cMajor,
            rung: 2,
            tempoBpm: 52,
            hands: HandConfiguration.together,
          ),
        ]),
        HandConfiguration.together,
      );
    });

    test('ignores together shown only with support', () {
      expect(
        opensOn([
          _played(
            _cMajor,
            rung: 1,
            tempoBpm: 52,
            hands: HandConfiguration.together,
          ),
        ]),
        HandConfiguration.right,
      );
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
    const geometry = KeyWheelGeometry(rings: 4);

    ({double x, double y}) point(double degrees, double radius) => (
      x: radius * math.sin(degrees * math.pi / 180),
      y: -radius * math.cos(degrees * math.pi / 180),
    );

    WheelCell? at(double degrees, double radius) {
      final p = point(degrees, radius);
      return geometry.cellAt(p.x, p.y);
    }

    test('places major outermost and melodic minor innermost', () {
      final (majorOuter, _) = geometry.ringOf(0);
      final (_, melodicInner) = geometry.ringOf(3);

      expect(at(0, majorOuter - 0.01), (sector: 0, ring: 0));
      expect(at(0, melodicInner + 0.01), (sector: 0, ring: 3));
    });

    test('widens its rings when there are fewer', () {
      const twoRings = KeyWheelGeometry(rings: 2);
      final (outer, inner) = twoRings.ringOf(1);

      expect(twoRings.ringWidth, geometry.ringWidth * 2);
      expect(inner, closeTo(KeyWheelGeometry.innerRadius, 1e-9));
      expect(twoRings.cellAt(0, -(outer + 0.01)), (sector: 0, ring: 0));
      expect(twoRings.cellAt(0, -(outer - 0.01)), (sector: 0, ring: 1));
    });

    test('finds a sector by its angle clockwise from the top', () {
      expect(at(90, 0.7)?.sector, 3);
      expect(at(14, 0.7)?.sector, 0);
      expect(at(16, 0.7)?.sector, 1);
      expect(at(346, 0.7)?.sector, 0);
      expect(at(344, 0.7)?.sector, 11);
    });

    test('gives each key a target clear of every other key', () {
      final targets = [
        for (var sector = 0; sector < 12; sector++)
          geometry.semanticTargetOf(sector),
      ];

      for (final (i, a) in targets.indexed) {
        expect(a.x.abs() + a.side / 2, lessThanOrEqualTo(1));
        expect(a.y.abs() + a.side / 2, lessThanOrEqualTo(1));
        for (final b in targets.skip(i + 1)) {
          final apart = math.max((a.x - b.x).abs(), (a.y - b.y).abs());
          expect(apart, greaterThanOrEqualTo(a.side - 1e-9));
        }
      }
      // About 52 logical pixels on a wheel 360 across.
      expect(targets.first.side * 180, greaterThan(48));
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
  attemptsByFamily: {
    TechnicalMaterial.scaleFamilyId: math.max(
      1,
      demonstrations.length + tempos.length,
    ),
  },
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
  TechnicalMaterial material, {
  required int rung,
  required double tempoBpm,
  HandConfiguration hands = HandConfiguration.right,
  int octaves = 1,
  double motorScore = 0.9,
}) => TempoObservation(
  materialId: material.materialId,
  hands: hands,
  handMotion: HandMotion.parallel,
  octaves: octaves,
  guidanceIndependence: rung,
  requestedTempoBpm: tempoBpm,
  tempoRatio: 1,
  motorScore: motorScore,
  occurredAt: _at(1),
);
