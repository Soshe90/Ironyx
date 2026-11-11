import '../../../core/database/daos/workout_dao.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/week_start.dart';

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

/// [weekStart] and [utcOffset] have to be the ones [weeks] was bucketed
/// with (see `WorkoutDao.watchWorkoutFrequency`), so that "this week" names
/// a bucket that exists in the series.
///
/// [rangeStart] and [firstWorkoutAt] decide where adherence starts counting;
/// see [trainedBeforeRange]. Without them it starts at the first trained
/// week of the series.
///
/// The streaks are counted over [history], every week since the first
/// workout, when it is given, and over [weeks] otherwise. Counted inside
/// the range they were capped by it: on "1M" neither could pass about five
/// weeks, and a streak begun before the range was cut at its start. Only
/// adherence is a figure about the range.
ConsistencySummary calculateConsistency(
    {required List<WorkoutFrequency> weeks,
    required int targetSessionsPerWeek,
    WeekStart weekStart = WeekStart.monday,
    Duration utcOffset = Duration.zero,
    DateTime? now,
    DateTime? rangeStart,
    DateTime? firstWorkoutAt,
    List<WorkoutFrequency>? history}) {
  final currentWeek = DateFormatters.weekBucketStart(
    now ?? DateTime.now(),
    weekStart: weekStart,
    utcOffset: utcOffset,
  );
  final List<WorkoutFrequency> streakWeeks = history ?? weeks;
  final current =
      currentStreakWeeks(weeks: streakWeeks, currentWeek: currentWeek);
  final longest = longestStreakWeeks(weeks: streakWeeks);
  if (weeks.isEmpty) {
    // Nothing in the range, but a streak from the history can still be
    // the longest one.
    return ConsistencySummary(
        currentStreakWeeks: current,
        longestStreakWeeks: longest,
        adherenceFraction: null,
        targetSessionsPerWeek: targetSessionsPerWeek,
        eligibleWeeks: 0,
        hitTargetWeeks: 0);
  }
  final ordered = [...weeks]
    ..sort((a, b) => a.weekStart.compareTo(b.weekStart));

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
  //
  // Unless training began before the range: then every week of the range
  // counts, the empty ones after a break included. Starting at the first
  // trained week there hid the break, so a lifter back for two weeks after
  // two months off read as fully consistent.
  final bool wholeRange = trainedBeforeRange(
    rangeStart: rangeStart,
    firstWorkoutAt: firstWorkoutAt,
  );
  final firstIndex =
      wholeRange ? 0 : ordered.indexWhere((week) => week.workoutCount > 0);
  //
  // A week only partly inside the window is not a miss yet: it counts once
  // it has met the target, and is left out until then. That is the week in
  // progress (counted from its first day, it dragged adherence down every
  // Monday) and, counting the whole range, its first week, which starts
  // before the range does and so holds only some of its sessions.
  bool partial(int index, WorkoutFrequency w) =>
      w.weekStart == currentWeek ||
      (wholeRange && index == 0 && rangeStart!.isAfter(w.weekStart));
  final eligible = firstIndex == -1
      ? const <WorkoutFrequency>[]
      : <WorkoutFrequency>[
          for (final (int i, WorkoutFrequency w)
              in ordered.sublist(firstIndex).indexed)
            if (!partial(firstIndex + i, w) ||
                w.workoutCount >= targetSessionsPerWeek)
              w,
        ];
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

/// Consecutive weeks with at least one workout, ending at [currentWeek].
///
/// The one definition of "streak", shared by Home's tile and Progress's
/// consistency card so the two cannot disagree. A week counts with any
/// finished workout in it. The week in progress does not break the streak
/// while it is still empty (the user may train later today), so counting
/// then starts from the week before.
///
/// [weeks] are weekly buckets as `WorkoutDao.watchWorkoutFrequency` emits
/// them, in any order; [currentWeek] is the bucket "this week" names. They
/// are matched by calendar day, not by `==`: stepping back a week across a
/// daylight-saving change lands on the right day but not always the same
/// instant, and an exact match then read the streak as broken.
///
/// The streak is only as long as the history it is given. Home passes the
/// whole history: counted from its eight-week window, it never showed more
/// than "8 wk".
int currentStreakWeeks({
  required List<WorkoutFrequency> weeks,
  required DateTime currentWeek,
}) {
  int key(DateTime d) => (d.year * 100 + d.month) * 100 + d.day;
  final Set<int> trained = <int>{
    for (final WorkoutFrequency w in weeks)
      if (w.workoutCount > 0) key(w.weekStart),
  };
  DateTime cursor = trained.contains(key(currentWeek))
      ? currentWeek
      : DateFormatters.previousWeek(currentWeek);
  int streak = 0;
  while (trained.contains(key(cursor))) {
    streak++;
    cursor = DateFormatters.previousWeek(cursor);
  }
  return streak;
}

/// The longest run of consecutive weeks with at least one workout.
///
/// Same rule as [currentStreakWeeks]: weeks matched by calendar day, in any
/// order, and a week missing from [weeks] breaks a run as a zero week does.
int longestStreakWeeks({required List<WorkoutFrequency> weeks}) {
  final List<DateTime> trained = <DateTime>[
    for (final WorkoutFrequency w in weeks)
      if (w.workoutCount > 0) w.weekStart,
  ]..sort();
  int longest = 0;
  int run = 0;
  DateTime? previous;
  for (final DateTime week in trained) {
    final bool follows =
        previous != null && _sameDay(DateFormatters.nextWeek(previous), week);
    if (previous != null && _sameDay(previous, week)) continue;
    run = follows ? run + 1 : 1;
    if (run > longest) longest = run;
    previous = week;
  }
  return longest;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Sessions per week over the time the range really covers.
///
/// [weeks] is the zero-filled weekly series for the range (see
/// `WorkoutDao.watchWorkoutFrequency`); [rangeDays] is the range's length,
/// null for all-time.
///
/// Dividing by the number of week buckets, as the page used to, counts
/// calendar weeks the range only touches: a 14-day range usually spans
/// three buckets, so six sessions read "2.0 / week" instead of 3.0. The
/// divisor is the range's own length instead, except where training began
/// inside it. Then it runs from the first trained week, as adherence and
/// the insights do, so a lifter two weeks in is not averaged over the
/// eleven weeks before they started. It is never less than one week, or a
/// first session today would read as seven a week.
///
/// With [firstWorkoutAt] before the range ([trainedBeforeRange]), training
/// did not begin inside it, so the whole range is the divisor: a break
/// inside the range lowers the average, as it should.
///
/// Null when nothing in the series was trained, unless training began
/// before the range: then nothing in it is a break, and the average is 0.
double? averageSessionsPerWeek({
  required List<WorkoutFrequency> weeks,
  required int? rangeDays,
  required DateTime now,
  DateTime? firstWorkoutAt,
}) {
  final int firstActive = weeks.indexWhere((w) => w.workoutCount > 0);
  if (firstActive == -1) {
    final bool aBreak = rangeDays != null &&
        trainedBeforeRange(
          rangeStart: now.subtract(Duration(days: rangeDays)),
          firstWorkoutAt: firstWorkoutAt,
        );
    return aBreak ? 0 : null;
  }
  final int total = weeks.fold(0, (sum, w) => sum + w.workoutCount);
  final bool wholeRange = rangeDays != null &&
      (firstActive == 0 ||
          trainedBeforeRange(
            rangeStart: now.subtract(Duration(days: rangeDays)),
            firstWorkoutAt: firstWorkoutAt,
          ));
  final double elapsedWeeks = wholeRange
      ? rangeDays / DateTime.daysPerWeek
      : now.difference(weeks[firstActive].weekStart).inMinutes /
          (Duration.minutesPerDay * DateTime.daysPerWeek);
  return total / (elapsedWeeks < 1 ? 1 : elapsedWeeks);
}

/// Whether training began before the range, so the range's weeks with
/// nothing in them are a break, not time before the user started.
///
/// False for all-time ([rangeStart] null), and while the first workout is
/// unknown ([firstWorkoutAt] null): the figures then count from the first
/// trained week of the series, which is right for someone who began inside
/// the range and was the rule for everyone before this was known.
bool trainedBeforeRange({
  required DateTime? rangeStart,
  required DateTime? firstWorkoutAt,
}) =>
    rangeStart != null &&
    firstWorkoutAt != null &&
    firstWorkoutAt.isBefore(rangeStart);
