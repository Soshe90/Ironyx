import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/daos/exercise_dao.dart';
import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/body_metrics.dart';
import '../../../core/database/tables/profiles.dart';
import '../../../core/database/tables/timer_sessions.dart';
import '../../../core/database/tables/workouts.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/week_start.dart';
import '../../../core/formatters/week_start_controller.dart';
import '../../../core/services/clock.dart';

part 'dashboard_providers.g.dart';

/// Most recent saved workout, for the "Last workout" card.
///
/// One independent provider per card (rather than a single combined
/// dashboard future) so a failure in one query never blanks the others.
@riverpod
Stream<Workout?> dashboardLastWorkout(Ref ref) =>
    ref.watch(workoutDaoProvider).watchAll(limit: 1).map(
          (rows) => rows.isEmpty ? null : rows.first,
        );

/// Most recent timer session, for the "Last timer" card.
@riverpod
Stream<TimerSession?> dashboardLastTimerSession(Ref ref) =>
    ref.watch(timerDaoProvider).watchAll(limit: 1).map(
          (rows) => rows.isEmpty ? null : rows.first,
        );

/// Exercise count and most recently added exercise, for the "Exercises" card.
@riverpod
Stream<LibrarySummary> dashboardLibrarySummary(Ref ref) =>
    ref.watch(exerciseDaoProvider).watchLibrarySummary();

/// Est. 1RM and trend for the most-logged lift, for the "Est. 1RM" card.
@riverpod
Stream<MostLoggedOneRM?> dashboardMostLoggedOneRM(Ref ref) =>
    ref.watch(workoutDaoProvider).watchMostLoggedExerciseOneRM();

/// Latest body weight entry, for the "Body weight" card.
@riverpod
Stream<BodyMetrics?> dashboardLatestBodyMetrics(Ref ref) =>
    ref.watch(bodyMetricsDaoProvider).watchLatest();

/// Average duration of completed workouts, for the dashboard progress cards.
@riverpod
Stream<double?> dashboardAverageWorkoutDuration(Ref ref) =>
    ref.watch(workoutDaoProvider).watchAverageDurationSeconds();

/// Profile settings used by dashboard targets.
@riverpod
Stream<Profile?> dashboardProfile(Ref ref) =>
    ref.watch(profileDaoProvider).watch();

// The windows below are keyed on [todayProvider] rather than
// `DateTime.now()`: the dashboard tab stays alive in the shell, so a window
// captured once at first build went stale as soon as the app outlived the
// day (or the week) it was opened in. Watching the day re-runs each query
// when the date changes and at no other time.
//
// They are keyed on [weekStartControllerProvider] as well, and every weekly
// query is given the device's UTC offset: the day strip, the weekly totals
// and "this week" must all mean the same seven days, in the user's time.

/// Completed workouts for each day in the current week, first day first.
@riverpod
Stream<List<WeekdayDistribution>> dashboardWeekdayDistribution(Ref ref) {
  final DateTime today = ref.watch(todayProvider);
  final WeekStart weekStart = ref.watch(weekStartControllerProvider);
  return ref.watch(workoutDaoProvider).watchWeekdayDistribution(
        since: DateFormatters.startOfWeek(today, weekStart),
        weekStart: weekStart,
        utcOffset: today.timeZoneOffset,
      );
}

/// Start of the hero window: midnight, [_heroWeeks] weeks before [today].
DateTime _heroWindowStart(DateTime today) =>
    DateTime(today.year, today.month, today.day - _heroWeeks * 7);

/// Last 8 weeks of training volume, for the dashboard's hero card
/// (headline number, trend vs. the prior week, and a sparkline).
@riverpod
Stream<List<WeeklyVolume>> dashboardWeeklyVolume(Ref ref) {
  final DateTime today = ref.watch(todayProvider);
  return ref.watch(workoutDaoProvider).watchWeeklyVolume(
        since: _heroWindowStart(today),
        weekStart: ref.watch(weekStartControllerProvider),
        utcOffset: today.timeZoneOffset,
      );
}

/// Last 8 weeks of completed-workout counts, paired with the volume series
/// above to answer "did I train enough this week", not just "how heavy".
@riverpod
Stream<List<WorkoutFrequency>> dashboardWeeklyFrequency(Ref ref) {
  final DateTime today = ref.watch(todayProvider);
  return ref.watch(workoutDaoProvider).watchWorkoutFrequency(
        since: _heroWindowStart(today),
        weekStart: ref.watch(weekStartControllerProvider),
        utcOffset: today.timeZoneOffset,
      );
}

/// Window backing the dashboard's "this week" card and its sparkline.
const int _heroWeeks = 8;

/// Same window, for copy that has to name it.
const int dashboardHeroWeeks = _heroWeeks;

/// Everything the "this week" hero card needs, resolved as one async value.
///
/// Volume and frequency come from two separate queries; combining them here
/// means the card has a single loading/error branch instead of rendering a
/// half-populated header while the second query is still in flight.
@riverpod
Future<WeekSnapshot> dashboardWeekSnapshot(Ref ref) async {
  // Watched before the awaits: dependencies registered after an async gap
  // are easy to lose if the provider rebuilds while it is suspended.
  final DateTime today = ref.watch(todayProvider);
  final WeekStart weekStart = ref.watch(weekStartControllerProvider);
  final List<WeeklyVolume> volume =
      await ref.watch(dashboardWeeklyVolumeProvider.future);
  final List<WorkoutFrequency> frequency =
      await ref.watch(dashboardWeeklyFrequencyProvider.future);
  return WeekSnapshot.from(
    volume: volume,
    frequency: frequency,
    weekStart: weekStart,
    today: today,
  );
}

/// Derived training status for the current week.
class WeekSnapshot {
  const WeekSnapshot({
    required this.volumeKg,
    required this.previousVolumeKg,
    required this.sessions,
    required this.streakWeeks,
    required this.volumeSeries,
    required this.hasHistory,
  });

  /// Builds the snapshot from the two weekly series.
  ///
  /// The DAO zero-fills gaps after SQLite's `GROUP BY`, but an empty result
  /// still means there is no history in the requested window. "This week" is
  /// therefore whichever bucket matches the current week start, not simply
  /// `last`; using `last` would report a stale week's volume after a rest week.
  ///
  /// [today] decides which bucket is "this week". It defaults to the device
  /// clock for callers that have no [todayProvider] to hand. [weekStart]
  /// has to be the one the two series were bucketed with, or no bucket
  /// would ever match.
  factory WeekSnapshot.from({
    required List<WeeklyVolume> volume,
    required List<WorkoutFrequency> frequency,
    required WeekStart weekStart,
    DateTime? today,
  }) {
    final DateTime thisWeek =
        DateFormatters.startOfWeek(today ?? DateTime.now(), weekStart);
    // By calendar day, not by 168 hours: across a daylight-saving change
    // that lands on 23:00 the day before, which is not the same day as any
    // bucket, so last week read as empty and the streak as broken.
    final DateTime lastWeek = DateFormatters.previousWeek(thisWeek);

    double volumeFor(DateTime week) {
      for (final WeeklyVolume w in volume) {
        if (_sameDay(w.weekStart, week)) return w.totalVolumeKg;
      }
      return 0;
    }

    int sessionsFor(DateTime week) {
      for (final WorkoutFrequency f in frequency) {
        if (_sameDay(f.weekStart, week)) return f.workoutCount;
      }
      return 0;
    }

    // Consecutive trained weeks ending at the current one. A rest week this
    // week does not immediately break the streak — the user may still train
    // later today — so counting starts from last week in that case.
    int streak = 0;
    DateTime cursor = sessionsFor(thisWeek) > 0 ? thisWeek : lastWeek;
    while (sessionsFor(cursor) > 0) {
      streak++;
      cursor = DateFormatters.previousWeek(cursor);
    }

    return WeekSnapshot(
      volumeKg: volumeFor(thisWeek),
      previousVolumeKg: volumeFor(lastWeek),
      sessions: sessionsFor(thisWeek),
      streakWeeks: streak,
      volumeSeries: <double>[
        for (final WeeklyVolume w in volume) w.totalVolumeKg
      ],
      hasHistory: volume.isNotEmpty,
    );
  }

  final double volumeKg;
  final double previousVolumeKg;
  final int sessions;

  /// Consecutive weeks with at least one completed workout.
  final int streakWeeks;
  final List<double> volumeSeries;

  /// Whether anything was logged inside the hero window. False both for a
  /// brand-new account and for a lapsed one, so copy keyed off this must
  /// talk about the window — not claim the user has never trained.
  final bool hasHistory;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
