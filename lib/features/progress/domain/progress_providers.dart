import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/body_metrics.dart';
import '../../../core/database/tables/profiles.dart';
import '../../../core/formatters/week_start_controller.dart';
import '../../../core/services/clock.dart';

import 'consistency_calculators.dart';
import 'strength_analytics.dart';

part 'progress_providers.g.dart';

/// Window applied to every chart on the Progress page.
///
/// `null` means all-time — the DAOs take a nullable `since` and omit the
/// lower bound for it, which is what makes imported historical data show up
/// instead of being clipped to a fixed recent window.
/// Windows are *rolling* — "the last 30 days", not "this calendar month" —
/// because the lower bound is `now - days`. User-facing range labels and
/// descriptions are selected in the presentation layer, where the active
/// locale is known.
enum ProgressRange {
  twoWeeks(14),
  month(30),
  quarter(90),
  year(365),
  all(null);

  const ProgressRange(this.days);

  final int? days;

  /// Lower bound of the window ending at [now]; null for all-time.
  ///
  /// Providers take the bound from [progressSinceProvider], never from a
  /// clock read of their own; see there.
  DateTime? sinceAt(DateTime now) =>
      days == null ? null : now.subtract(Duration(days: days!));
}

/// Lower bound of [range] for every Progress query, anchored to
/// [localNowProvider].
///
/// Each provider used to read `DateTime.now()` once, when it was built. The
/// Progress tab is kept alive by the shell, and a Drift stream re-runs on
/// new data with the bound it was created with, so an app left in memory
/// for a week showed a "last 14 days" that had become the 14 days before
/// last week, while the weekly series (which rebuild with the day) moved
/// on: two cards on one page disagreeing about the same range.
/// [localNowProvider] changes at the next part of the day, at midnight and
/// when the app returns to the foreground, so every query moves together,
/// a few times a day at most.
@riverpod
DateTime? progressSince(Ref ref, ProgressRange range) =>
    range.sinceAt(ref.watch(localNowProvider));

/// The selected range, shared by every chart so they always agree.
@riverpod
class ProgressRangeController extends _$ProgressRangeController {
  @override
  ProgressRange build() => ProgressRange.quarter;

  void set(ProgressRange range) => state = range;
}

/// Estimated-1RM series for one exercise.
///
/// Keyed on the range enum rather than a `DateTime since`: a timestamp
/// changes on every read, so it would defeat provider caching and
/// re-subscribe the stream on each rebuild.
@riverpod
Stream<List<OneRMSeriesPoint>> oneRmSeries(
  Ref ref,
  String exerciseId,
  ProgressRange range,
) =>
    ref.watch(workoutDaoProvider).watchOneRMSeries(
          exerciseId,
          since: ref.watch(progressSinceProvider(range)),
        );

@riverpod
Stream<List<SessionVolumeLoad>> sessionVolumeLoad(
  Ref ref,
  String exerciseId,
  ProgressRange range,
) =>
    ref.watch(workoutDaoProvider).watchSessionVolumeLoad(
          exerciseId,
          since: ref.watch(progressSinceProvider(range)),
        );

// Every series grouped by week or by weekday is given the first day of the
// week chosen in Settings and the device's UTC offset, so that Progress,
// the dashboard and the history calendar all mean the same seven days, in
// the user's own time. The offset is read off [todayProvider], which also
// re-runs these when the day changes.

@riverpod
Stream<List<WeeklyVolume>> weeklyVolumeSeries(Ref ref, ProgressRange range) =>
    ref.watch(workoutDaoProvider).watchWeeklyVolume(
          since: ref.watch(progressSinceProvider(range)),
          weekStart: ref.watch(weekStartControllerProvider),
          utcOffset: ref.watch(todayProvider).timeZoneOffset,
        );

@riverpod
Stream<List<WorkoutFrequency>> workoutFrequencySeries(
  Ref ref,
  ProgressRange range,
) =>
    ref.watch(workoutDaoProvider).watchWorkoutFrequency(
          since: ref.watch(progressSinceProvider(range)),
          weekStart: ref.watch(weekStartControllerProvider),
          utcOffset: ref.watch(todayProvider).timeZoneOffset,
        );

@riverpod
Stream<List<SessionRpe>> rpeAnalytics(Ref ref, ProgressRange range) => ref
    .watch(workoutDaoProvider)
    .watchRpeAnalytics(since: ref.watch(progressSinceProvider(range)));

@riverpod
Stream<List<SessionRest>> restAnalytics(Ref ref, ProgressRange range) => ref
    .watch(workoutDaoProvider)
    .watchRestAnalytics(since: ref.watch(progressSinceProvider(range)));

@riverpod
Stream<BalanceRatios> balanceRatios(Ref ref, ProgressRange range) => ref
    .watch(workoutDaoProvider)
    .watchBalanceRatios(since: ref.watch(progressSinceProvider(range)));

@riverpod
Stream<List<WeeklyMuscleGroupVolume>> weeklyMuscleGroupVolumeSeries(
  Ref ref,
  ProgressRange range,
) =>
    ref.watch(workoutDaoProvider).watchWeeklyMuscleGroupVolume(
          since: ref.watch(progressSinceProvider(range)),
          weekStart: ref.watch(weekStartControllerProvider),
          utcOffset: ref.watch(todayProvider).timeZoneOffset,
        );

@riverpod
Stream<List<RepRangeDistribution>> repRangeDistribution(
        Ref ref, ProgressRange range) =>
    ref.watch(workoutDaoProvider).watchRepRangeDistribution(
        since: ref.watch(progressSinceProvider(range)));

@riverpod
Stream<List<WeekdayDistribution>> weekdayDistribution(
        Ref ref, ProgressRange range) =>
    ref.watch(workoutDaoProvider).watchWeekdayDistribution(
          since: ref.watch(progressSinceProvider(range)),
          weekStart: ref.watch(weekStartControllerProvider),
          utcOffset: ref.watch(todayProvider).timeZoneOffset,
        );

@riverpod
Future<ConsistencySummary> consistencySummary(
    Ref ref, ProgressRange range) async {
  // Watched before the awaits: dependencies registered after an async gap
  // are easy to lose if the provider rebuilds while it is suspended.
  final weekStart = ref.watch(weekStartControllerProvider);
  final Duration utcOffset = ref.watch(todayProvider).timeZoneOffset;
  final Future<List<WorkoutFrequency>> weeksFuture =
      ref.watch(workoutFrequencySeriesProvider(range).future);
  // Watched, not read once: a target changed in Settings used to leave
  // adherence measured against the old one until the app restarted.
  final Future<Profile?> profileFuture =
      ref.watch(progressProfileProvider.future);
  final weeks = await weeksFuture;
  final Profile? profile = await profileFuture;
  return calculateConsistency(
    weeks: weeks,
    targetSessionsPerWeek:
        profile?.weeklySessionTarget ?? defaultWeeklySessionTarget,
    weekStart: weekStart,
    utcOffset: utcOffset,
  );
}

@riverpod
Stream<List<MuscleGroupVolume>> muscleGroupSeries(
  Ref ref,
  ProgressRange range,
) =>
    ref
        .watch(workoutDaoProvider)
        .watchMuscleGroupVolume(since: ref.watch(progressSinceProvider(range)));

/// Muscle volume in the range immediately preceding the selected range.
/// All-time has no finite preceding window, so it intentionally returns none.
@riverpod
Stream<List<MuscleGroupVolume>> previousMuscleGroupSeries(
  Ref ref,
  ProgressRange range,
) {
  final since = ref.watch(progressSinceProvider(range));
  if (since == null) return Stream.value(const <MuscleGroupVolume>[]);
  final duration = Duration(days: range.days!);
  return ref.watch(workoutDaoProvider).watchMuscleGroupVolume(
        since: since.subtract(duration),
        until: since,
      );
}

/// Number of PR-setting workouts in the selected range.
@riverpod
Stream<int> recentPersonalRecords(Ref ref, ProgressRange range) => ref
    .watch(workoutDaoProvider)
    .watchPersonalRecordWorkoutIds(
        since: ref.watch(progressSinceProvider(range)))
    .map((ids) => ids.length);

@riverpod
Stream<Profile?> progressProfile(Ref ref) =>
    ref.watch(profileDaoProvider).watch();

/// The newest body-metric entry, whatever the range.
@riverpod
Stream<BodyMetrics?> progressLatestBodyMetrics(Ref ref) =>
    ref.watch(bodyMetricsDaoProvider).watchLatest();

/// Body-metric entries inside the selected range.
///
/// Ranged like every other series on the page: the range control sits above
/// all of them and claims to govern all of them, so an all-time body-weight
/// chart under a "1M" selection was simply wrong.
@riverpod
Stream<List<BodyMetrics>> bodyMetricsSeries(Ref ref, ProgressRange range) => ref
    .watch(bodyMetricsDaoProvider)
    .watchAll(since: ref.watch(progressSinceProvider(range)));

/// Exercises with logged sets, most-trained first — the 1RM picker's source.
@riverpod
Stream<List<LoggedExercise>> loggedExercises(Ref ref) =>
    ref.watch(workoutDaoProvider).watchLoggedExercises();

@riverpod
Future<List<RelativeStrength>> relativeStrengths(
  Ref ref,
  ProgressRange range,
) async {
  // All three watched before the first await (see consistencySummary).
  // The weigh-in used to be read once, so logging a new one left every
  // ratio on the old body weight; and the 30-day cut-off read its own
  // clock, so a stale weigh-in kept counting while the tab stayed open.
  final DateTime now = ref.watch(localNowProvider);
  final Future<BodyMetrics?> bodyFuture =
      ref.watch(progressLatestBodyMetricsProvider.future);
  final Future<List<StrengthChange>> changesFuture =
      ref.watch(strengthChangeProvider(range).future);
  final body = await bodyFuture;
  if (body == null || body.weightKg <= 0) return const [];
  final measuredAt = body.date;
  if (now.difference(measuredAt).inDays > 30) return const [];
  final changes = await changesFuture;
  return [
    for (final row in changes)
      RelativeStrength(
        exerciseId: row.exerciseId,
        exerciseName: row.exerciseName,
        oneRmKg: row.currentBestKg,
        bodyWeightKg: body.weightKg,
        measuredAt: measuredAt,
      ),
  ];
}

/// Best estimated 1RM per lift in the selected window vs the window before.
///
/// This is the "did I get stronger" series, as opposed to the volume
/// series which answers "how much work did I do".
@riverpod
Stream<List<StrengthChange>> strengthChange(Ref ref, ProgressRange range) => ref
    .watch(workoutDaoProvider)
    .watchStrengthChange(since: ref.watch(progressSinceProvider(range)));

/// Best set and prior best for each exercise in one saved workout.
@riverpod
Stream<List<ExercisePerformance>> workoutPerformance(
  Ref ref,
  String workoutId,
) =>
    ref.watch(workoutDaoProvider).watchWorkoutPerformance(workoutId);
