import '../../../core/database/daos/workout_dao.dart';
import '../../../core/formatters/date_formatters.dart';

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
  final currentWeek = DateFormatters.utcWeekStart(now ?? DateTime.now());
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

  // `weeks` is zero-filled from the selected range's nominal start (see
  // `WorkoutDao._fillWeekGaps`) so charts can show "you started partway
  // through this range" — but adherence is a plain percentage with no
  // chart alongside it, and counting weeks that pre-date the user's
  // first-ever workout as missed target understates it for anyone whose
  // training history is shorter than the range: a lifter two weeks in who
  // picks "3 months" saw 2/13 weeks hit target read as 15%, not the 100%
  // they actually managed. The eligible window starts at the first week
  // with any activity; a week with zero sessions *after* training began is
  // still a real miss and stays counted.
  final firstActiveIndex = ordered.indexWhere((week) => week.workoutCount > 0);
  final eligible = firstActiveIndex == -1
      ? const <WorkoutFrequency>[]
      : ordered.sublist(firstActiveIndex);
  final hits =
      eligible.where((w) => w.workoutCount >= targetSessionsPerWeek).length;
  return ConsistencySummary(
      currentStreakWeeks: current,
      longestStreakWeeks: longest,
      adherenceFraction: eligible.isEmpty ? null : hits / eligible.length,
      targetSessionsPerWeek: targetSessionsPerWeek,
      eligibleWeeks: eligible.length,
      hitTargetWeeks: hits);
}
