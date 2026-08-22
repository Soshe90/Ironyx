import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/daos/exercise_dao.dart';
import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/body_metrics.dart';
import '../../../core/database/tables/timer_sessions.dart';
import '../../../core/database/tables/workouts.dart';
import '../../../core/formatters/date_formatters.dart';

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

/// Last 8 weeks of training volume, for the dashboard's hero card
/// (headline number, trend vs. the prior week, and a sparkline).
@riverpod
Stream<List<WeeklyVolume>> dashboardWeeklyVolume(Ref ref) =>
    ref.watch(workoutDaoProvider).watchWeeklyVolume(
          since: DateTime.now().subtract(const Duration(days: _heroWeeks * 7)),
        );

/// Last 8 weeks of completed-workout counts, paired with the volume series
/// above to answer "did I train enough this week", not just "how heavy".
@riverpod
Stream<List<WorkoutFrequency>> dashboardWeeklyFrequency(Ref ref) =>
    ref.watch(workoutDaoProvider).watchWorkoutFrequency(
          since: DateTime.now().subtract(const Duration(days: _heroWeeks * 7)),
        );

/// Window backing the dashboard's "this week" card and its sparkline.
const int _heroWeeks = 8;

/// Everything the "this week" hero card needs, resolved as one async value.
///
/// Volume and frequency come from two separate queries; combining them here
/// means the card has a single loading/error branch instead of rendering a
/// half-populated header while the second query is still in flight.
@riverpod
Future<WeekSnapshot> dashboardWeekSnapshot(Ref ref) async {
  final List<WeeklyVolume> volume =
      await ref.watch(dashboardWeeklyVolumeProvider.future);
  final List<WorkoutFrequency> frequency =
      await ref.watch(dashboardWeeklyFrequencyProvider.future);
  return WeekSnapshot.from(volume: volume, frequency: frequency);
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
  /// The series only contain weeks that have workouts — SQLite's `GROUP BY`
  /// emits no row for a week you did not train. So "this week" is whichever
  /// bucket matches the current week start, not simply `last`; using `last`
  /// would report a stale week's volume as the current one after a rest week.
  factory WeekSnapshot.from({
    required List<WeeklyVolume> volume,
    required List<WorkoutFrequency> frequency,
  }) {
    final DateTime thisWeek = DateFormatters.startOfWeek(DateTime.now());
    final DateTime lastWeek =
        thisWeek.subtract(const Duration(days: DateTime.daysPerWeek));

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
      cursor = cursor.subtract(const Duration(days: DateTime.daysPerWeek));
    }

    return WeekSnapshot(
      volumeKg: volumeFor(thisWeek),
      previousVolumeKg: volumeFor(lastWeek),
      sessions: sessionsFor(thisWeek),
      streakWeeks: streak,
      volumeSeries: <double>[for (final WeeklyVolume w in volume) w.totalVolumeKg],
      hasHistory: volume.isNotEmpty,
    );
  }

  final double volumeKg;
  final double previousVolumeKg;
  final int sessions;

  /// Consecutive weeks with at least one completed workout.
  final int streakWeeks;
  final List<double> volumeSeries;

  /// False for a brand-new account, which gets an onboarding empty state
  /// rather than a wall of zeroes.
  final bool hasHistory;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
