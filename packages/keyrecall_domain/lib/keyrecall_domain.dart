/// The KeyRecall practice domain: what can be played, how it can be played,
/// and which competencies each combination creates an opportunity to observe.
///
/// An [Exercise] bundles a [TechnicalMaterial], an [ExercisePattern],
/// [ExecutionConditions], a [GuidanceContext], and the [MotorOpportunity]
/// sites its event structure exposes. `Exercise.structuralQ` maps that bundle
/// onto [Competency] values; nothing here reads or stores learner state.
library;

export 'src/admission_band.dart';
export 'src/arpeggio_catalog.dart';
export 'src/competency.dart';
export 'src/curriculum.dart';
export 'src/exercise.dart';
export 'src/execution_conditions.dart';
export 'src/exercise_fingering.dart';
export 'src/fingering.dart';
export 'src/guidance_context.dart';
export 'src/hand_path.dart';
export 'src/instrument_profile.dart';
export 'src/material_topology.dart';
export 'src/motor_opportunity.dart';
export 'src/performance_transcript.dart';
export 'src/pitch_spelling.dart';
export 'src/presentation_conditions.dart';
export 'src/practice_goal.dart';
export 'src/realization.dart';
export 'src/scale_catalog.dart';
export 'src/spelled_pitch.dart';
export 'src/technical_material.dart';
export 'src/tempo_ladder.dart';
