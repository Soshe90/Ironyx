import '../../../core/database/daos/workout_dao.dart';

class LinearTrend {
  const LinearTrend(
      {required this.slopeKgPerMonth,
      required this.interceptKg,
      required this.pointCount});
  final double slopeKgPerMonth;
  final double interceptKg;
  final int pointCount;
  bool get isReliable => pointCount >= 4;
}

/// Least-squares trend over elapsed days. Returns null for fewer than two
/// distinct dates; callers should avoid presenting a confident trend for a
/// very small sample.
LinearTrend? linearTrend(List<OneRMSeriesPoint> points) {
  if (points.length < 2) return null;
  final ordered = [...points]..sort((a, b) => a.date.compareTo(b.date));
  final origin = ordered.first.date;
  final xs = [
    for (final point in ordered)
      point.date.difference(origin).inMinutes / 1440.0 / 30.4375
  ];
  final ys = [for (final point in ordered) point.estimated1RM];
  final xMean = xs.reduce((a, b) => a + b) / xs.length;
  final yMean = ys.reduce((a, b) => a + b) / ys.length;
  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < xs.length; i++) {
    numerator += (xs[i] - xMean) * (ys[i] - yMean);
    denominator += (xs[i] - xMean) * (xs[i] - xMean);
  }
  if (denominator == 0) return null;
  return LinearTrend(
      slopeKgPerMonth: numerator / denominator,
      interceptKg: yMean - (numerator / denominator) * xMean,
      pointCount: points.length);
}

class RelativeStrength {
  const RelativeStrength(
      {required this.exerciseId,
      required this.exerciseName,
      required this.oneRmKg,
      required this.bodyWeightKg,
      required this.measuredAt});
  final String exerciseId;
  final String exerciseName;
  final double oneRmKg;
  final double bodyWeightKg;
  final DateTime measuredAt;
  double get ratio => oneRmKg / bodyWeightKg;
}

class NormalizedLiftSeries {
  const NormalizedLiftSeries(
      {required this.exerciseId,
      required this.exerciseName,
      required this.points});
  final String exerciseId;
  final String exerciseName;
  final List<NormalizedPoint> points;
}

class NormalizedPoint {
  const NormalizedPoint({required this.date, required this.percentOfStart});
  final DateTime date;
  final double percentOfStart;
}
