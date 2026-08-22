/// The KeyRecall practice domain: what can be played, how it can be played,
/// and which competencies each combination creates an opportunity to observe.
///
/// An [Exercise] bundles a [TechnicalMaterial], an [ExercisePattern],
/// [ExecutionConditions], a [GuidanceContext], and the [MotorOpportunity]
/// sites its event structure exposes. `Exercise.structuralQ` maps that bundle
/// onto [Competency] values; nothing here reads or stores learner state.
library;

export 'src/competency.dart';
export 'src/exercise.dart';
export 'src/execution_conditions.dart';
export 'src/guidance_context.dart';
export 'src/instrument_profile.dart';
export 'src/motor_opportunity.dart';
export 'src/scale_catalog.dart';
export 'src/technical_material.dart';
