import '../../../core/database/daos/workout_dao.dart';

const int defaultWeeklySessionTarget = 3;

class ConsistencySummary {
  const ConsistencySummary(
      {required this.currentStreakWeeks,
      required this.longestStreakWeeks,
      required this.adherenceFraction,
      required this.targetSessionsPerWeek,
      required this.eligibleWeeks,
      required this.hitTargetWeeks});
  final int currentStreakWeeks;
  final int longestStreakWeeks;
  final double? adherenceFraction;
  final int targetSessionsPerWeek;
  final int eligibleWeeks;
  final int hitTargetWeeks;
}

ConsistencySummary calculateConsistency(
    {required List<WorkoutFrequency> weeks,
    required int targetSessionsPerWeek,
    DateTime? now}) {
  if (weeks.isEmpty) {
    return ConsistencySummary(
        currentStreakWeeks: 0,
        longestStreakWeeks: 0,
        adherenceFraction: null,
        targetSessionsPerWeek: targetSessionsPerWeek,
        eligibleWeeks: 0,
        hitTargetWeeks: 0);
  }
  final ordered = [...weeks]
    ..sort((a, b) => a.weekStart.compareTo(b.weekStart));
  var longest = 0;
  var run = 0;
  for (final week in ordered) {
    if (week.workoutCount > 0) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 0;
    }
  }
  final currentWeek = _monday(now ?? DateTime.now());
  final lastWeek = currentWeek.subtract(const Duration(days: 7));
  int count(DateTime start) => ordered
      .where((w) => w.weekStart == start)
      .fold(0, (sum, w) => sum + w.workoutCount);
  var cursor = count(currentWeek) > 0 ? currentWeek : lastWeek;
  var current = 0;
  while (count(cursor) > 0) {
    current++;
    cursor = cursor.subtract(const Duration(days: 7));
  }
  final hits =
      ordered.where((w) => w.workoutCount >= targetSessionsPerWeek).length;
  return ConsistencySummary(
      currentStreakWeeks: current,
      longestStreakWeeks: longest,
      adherenceFraction: hits / ordered.length,
      targetSessionsPerWeek: targetSessionsPerWeek,
      eligibleWeeks: ordered.length,
      hitTargetWeeks: hits);
}

DateTime _monday(DateTime date) {
  final utc = date.toUtc();
  final day = DateTime.utc(utc.year, utc.month, utc.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}
