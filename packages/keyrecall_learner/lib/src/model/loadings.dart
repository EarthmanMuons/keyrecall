import 'package:keyrecall_domain/keyrecall_domain.dart';

/// `q_{e,k}`: how much each competency in [q] counts toward a prediction.
///
/// Absent better information, V1 splits the credit evenly among whichever
/// competencies are in play. Equal loading avoids inventing precise relative
/// weights before real data exists.
///
/// Competencies outside [q] are absent from the result rather than mapped to
/// zero; read with a `?? 0.0` fallback.
Map<Competency, double> normalizedLoadings(Set<Competency> q) {
  if (q.isEmpty) return const {};
  final weight = 1.0 / q.length;
  return {for (final competency in q) competency: weight};
}

/// `q_{e,k}` restricted to and renormalized within the motor channel.
Map<Competency, double> motorLoadings(Set<Competency> q) =>
    normalizedLoadings(q.intersection(motorCompetencies));

/// `q_{e,k}` restricted to and renormalized within the coordination channel.
Map<Competency, double> coordinationLoadings(Set<Competency> q) =>
    normalizedLoadings(q.intersection(coordinationCompetencies));

/// `q_{e,k}` restricted to and renormalized within the topology channel.
///
/// Normalized separately from [motorLoadings]: sharing one denominator would
/// let the presence of a topology opportunity dilute the motor predictor.
Map<Competency, double> topologyLoadings(Set<Competency> q) =>
    normalizedLoadings(q.intersection(topologyCompetencies));
