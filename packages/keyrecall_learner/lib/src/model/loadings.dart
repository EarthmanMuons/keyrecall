import 'package:keyrecall_domain/keyrecall_domain.dart';

/// `q_{e,k}`: how much each competency in [q] counts toward a prediction.
///
/// V1 splits the credit evenly among whichever competencies are in play.
///
/// Emitted in [Competency.values] order, whatever order [q] iterates in. The
/// channel predictions sum these as they arrive, floating-point addition is not
/// associative, and a state hash is exact, so a set built in a different order
/// would replay to a different state.
///
/// Competencies outside [q] are absent from the result rather than mapped to
/// zero; read with a `?? 0.0` fallback.
Map<Competency, double> normalizedLoadings(Set<Competency> q) {
  if (q.isEmpty) return const {};
  final weight = 1.0 / q.length;
  return {
    for (final competency in Competency.values)
      if (q.contains(competency)) competency: weight,
  };
}

/// `q_{e,k}` restricted to and renormalized within the motor channel.
Map<Competency, double> motorLoadings(Set<Competency> q) =>
    normalizedLoadings(q.intersection(motorCompetencies));

/// `q_{e,k}` restricted to and renormalized within the coordination channel.
Map<Competency, double> coordinationLoadings(Set<Competency> q) =>
    normalizedLoadings(q.intersection(coordinationCompetencies));

/// `q_{e,k}` restricted to and renormalized within the topology channel.
///
/// Normalized separately from [motorLoadings], so a topology opportunity cannot
/// dilute the motor predictor.
Map<Competency, double> topologyLoadings(Set<Competency> q) =>
    normalizedLoadings(q.intersection(topologyCompetencies));
