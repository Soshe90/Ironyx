import '../../../core/database/daos/workout_dao.dart';

/// The figures the Progress cards print, worked out from the series they
/// plot.
///
/// These were folds inside `build` methods, where only a pumped widget
/// could test them and where the hero and the cards each kept their own
/// copy. Pure functions over the DAO rows, so each rule has one place and
/// a unit test.

/// Total volume and the number of weeks that had any, over a zero-filled
/// weekly series.
///
/// The series' length is elapsed weeks, not trained ones, which is why the
/// trained ones are counted explicitly.
({double totalKg, int activeWeeks}) summarizeWeeklyVolume(
  List<WeeklyVolume> weeks,
) {
  double total = 0;
  int active = 0;
  for (final WeeklyVolume w in weeks) {
    total += w.totalVolumeKg;
    if (w.totalVolumeKg > 0) active++;
  }
  return (totalKg: total, activeWeeks: active);
}

/// Workouts and the number of weeks that had any, over a zero-filled
/// weekly series.
({int workouts, int activeWeeks}) summarizeWeeklyFrequency(
  List<WorkoutFrequency> weeks,
) {
  int total = 0;
  int active = 0;
  for (final WorkoutFrequency w in weeks) {
    total += w.workoutCount;
    if (w.workoutCount > 0) active++;
  }
  return (workouts: total, activeWeeks: active);
}

/// Average effort (RPE) across the sessions; null when no set was rated.
///
/// Weighted by the sets each session rated, like [summarizeRest]: it is
/// the average over every rated set of the range. Counting each session
/// once let a session with a single all-out set outweigh one with twenty
/// rated sets, and made effort and rest follow two different rules on the
/// same card.
double? averageSessionRpe(List<SessionRpe> sessions) {
  int sets = 0;
  double sum = 0;
  for (final SessionRpe s in sessions) {
    sets += s.ratedSetCount;
    sum += s.averageRpe * s.ratedSetCount;
  }
  return sets == 0 ? null : sum / sets;
}

/// Average rest across the sessions, and how many timed rests it stands on.
///
/// Weighted by the rests each session recorded, so a session with one
/// timed rest does not count as much as one with twenty. The average is
/// null when nothing was timed: "0 s" would claim rests that never were.
({double? averageSeconds, int restCount}) summarizeRest(
  List<SessionRest> sessions,
) {
  int count = 0;
  double seconds = 0;
  for (final SessionRest s in sessions) {
    count += s.recordedSetCount;
    seconds += s.averageRestSeconds * s.recordedSetCount;
  }
  return (
    averageSeconds: count == 0 ? null : seconds / count,
    restCount: count
  );
}

/// Id of the bucket that folds the smallest muscle groups together.
const String otherMuscleGroupId = '_other';

/// Muscle groups ranked as the share bars show them.
///
/// Groups with no volume are dropped: a group linked only through
/// bodyweight sets totals 0 kg, and as a ranked bar it is an empty track
/// that reads like missing data. Past [slots] groups (one per palette
/// colour) the rest fold into one [otherMuscleGroupId] row named
/// [otherName], already in the user's language. [all] arrives largest
/// first from the DAO, and keeps that order.
///
/// [total] and [largest] are over the returned rows, so shares add up to
/// the whole and the largest bar fills its track.
({List<MuscleGroupVolume> groups, double total, double largest})
    groupMuscleVolume(
  List<MuscleGroupVolume> all, {
  required int slots,
  required String otherName,
}) {
  final List<MuscleGroupVolume> trained = <MuscleGroupVolume>[
    for (final MuscleGroupVolume g in all)
      if (g.totalVolumeKg > 0) g,
  ];
  final List<MuscleGroupVolume> groups = trained.length <= slots
      ? trained
      : <MuscleGroupVolume>[
          ...trained.take(slots),
          MuscleGroupVolume(
            muscleId: otherMuscleGroupId,
            muscleName: otherName,
            totalVolumeKg: trained
                .skip(slots)
                .fold<double>(0, (sum, g) => sum + g.totalVolumeKg),
          ),
        ];
  double total = 0;
  double largest = 0;
  for (final MuscleGroupVolume g in groups) {
    total += g.totalVolumeKg;
    if (g.totalVolumeKg > largest) largest = g.totalVolumeKg;
  }
  return (groups: groups, total: total, largest: largest);
}

/// One muscle group's volume week by week, on the weeks of [axis].
///
/// [axis] is the range's zero-filled weekly-volume series, so a week the
/// group was not trained is a zero in the right place rather than two bars
/// drawn side by side. Should it be empty (that series failed or has not
/// loaded), the group's own weeks are used, in order. Rows for other
/// groups are ignored; rows for the same group and week are added up.
({List<DateTime> weeks, List<double> values}) muscleWeeklySeries({
  required String muscleId,
  required List<WeeklyMuscleGroupVolume> rows,
  required List<WeeklyVolume> axis,
}) {
  final Map<DateTime, double> byWeek = <DateTime, double>{};
  for (final WeeklyMuscleGroupVolume row in rows) {
    if (row.muscleId != muscleId) continue;
    byWeek[row.weekStart] = (byWeek[row.weekStart] ?? 0) + row.totalVolumeKg;
  }
  final List<DateTime> weeks = axis.isNotEmpty
      ? <DateTime>[for (final WeeklyVolume w in axis) w.weekStart]
      : (byWeek.keys.toList()..sort());
  return (
    weeks: weeks,
    values: <double>[for (final DateTime week in weeks) byWeek[week] ?? 0],
  );
}
