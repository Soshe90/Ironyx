import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/features/progress/domain/strength_analytics.dart';

void main() {
  test('fits a positive monthly e1RM trend', () {
    final start = DateTime.utc(2026, 1, 1);
    final trend = linearTrend([
      OneRMSeriesPoint(date: start, estimated1RM: 100),
      OneRMSeriesPoint(date: DateTime.utc(2026, 2, 1), estimated1RM: 102),
      OneRMSeriesPoint(date: DateTime.utc(2026, 3, 1), estimated1RM: 104),
      OneRMSeriesPoint(date: DateTime.utc(2026, 4, 1), estimated1RM: 106),
    ]);
    expect(trend, isNotNull);
    expect(trend!.slopeKgPerMonth, closeTo(2, .1));
    expect(trend.isReliable, isTrue);
  });

  test('does not invent a slope for a single point or same date', () {
    expect(
        linearTrend([
          OneRMSeriesPoint(date: DateTime.utc(2026, 1, 1), estimated1RM: 100),
        ]),
        isNull);
    expect(
        linearTrend([
          OneRMSeriesPoint(date: DateTime.utc(2026, 1, 1), estimated1RM: 100),
          OneRMSeriesPoint(date: DateTime.utc(2026, 1, 1), estimated1RM: 110),
        ]),
        isNull);
  });
}
