import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  PresentationConditions conditions({
    PitchCue pitchCue = PitchCue.full,
    CueModality? cueModality = CueModality.keyboard,
    MotorCue motorCue = MotorCue.none,
    PerformanceFeedback performanceFeedback = PerformanceFeedback.neutralEcho,
    TempoSupport tempoSupport = TempoSupport.countInOnly,
  }) => PresentationConditions(
    pitchCue: pitchCue,
    cueModality: cueModality,
    motorCue: motorCue,
    performanceFeedback: performanceFeedback,
    tempoSupport: tempoSupport,
  );

  group('cue and modality', () {
    test('a supplied cue needs a way to present it', () {
      expect(
        () => conditions(pitchCue: PitchCue.full, cueModality: null),
        throwsArgumentError,
      );
    });

    test('a modality with nothing to present is refused', () {
      expect(
        () =>
            conditions(pitchCue: PitchCue.none, cueModality: CueModality.staff),
        throwsArgumentError,
      );
    });

    test('supplying material is a question about the cue, not the surface', () {
      expect(PitchCue.none.suppliesMaterial, isFalse);
      for (final cue in [
        PitchCue.startOnly,
        PitchCue.limitedLookahead,
        PitchCue.full,
      ]) {
        expect(cue.suppliesMaterial, isTrue);
      }
    });

    test('only notation demands decoding', () {
      expect(
        conditions(cueModality: CueModality.keyboard).demandsNotationDecoding,
        isFalse,
      );
      expect(
        conditions(cueModality: CueModality.staff).demandsNotationDecoding,
        isTrue,
      );
      expect(
        conditions(
          pitchCue: PitchCue.none,
          cueModality: null,
        ).demandsNotationDecoding,
        isFalse,
        reason:
            'showing no notation is not a reading task, and must not be '
            'read as a harder one',
      );
    });
  });

  group('pairing with guidance', () {
    test('both supported rungs need something supplied', () {
      for (final guidance in [
        GuidanceContext.continuouslyCued,
        GuidanceContext.notesPreviewedOnly,
      ]) {
        expect(conditions().suitsGuidance(guidance), isTrue);
        expect(
          conditions(
            pitchCue: PitchCue.none,
            cueModality: null,
          ).suitsGuidance(guidance),
          isFalse,
        );
      }
    });

    test('an unguided attempt must supply nothing', () {
      expect(
        conditions(
          pitchCue: PitchCue.none,
          cueModality: null,
        ).suitsGuidance(GuidanceContext.unguided),
        isTrue,
      );
      expect(conditions().suitsGuidance(GuidanceContext.unguided), isFalse);
    });

    test('the other three channels are free of the rung', () {
      for (final guidance in GuidanceContext.ladder) {
        final supplied = guidance.isMaterialSupplied;
        for (final motor in MotorCue.values) {
          for (final feedback in PerformanceFeedback.values) {
            for (final tempo in TempoSupport.values) {
              expect(
                conditions(
                  pitchCue: supplied ? PitchCue.full : PitchCue.none,
                  cueModality: supplied ? CueModality.keyboard : null,
                  motorCue: motor,
                  performanceFeedback: feedback,
                  tempoSupport: tempo,
                ).suitsGuidance(guidance),
                isTrue,
                reason:
                    'fingering, feedback, and tempo are their own axes: no '
                    'value of them makes a presentation illegal under a rung',
              );
            }
          }
        }
      }
    });
  });

  group('performance feedback', () {
    test('separates showing an attempt back from judging it', () {
      expect(PerformanceFeedback.neutralEcho.judgesDuringAttempt, isFalse);
      expect(PerformanceFeedback.evaluative.judgesDuringAttempt, isTrue);
      expect(PerformanceFeedback.none.judgesDuringAttempt, isFalse);
    });
  });

  test('value equality, so a presentation can be compared and stored', () {
    expect(conditions(), conditions());
    expect(
      conditions(),
      isNot(conditions(performanceFeedback: PerformanceFeedback.none)),
    );
    expect(conditions(), isNot(conditions(cueModality: CueModality.staff)));
  });
}
