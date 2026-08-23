import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/body_metrics.dart';
import '../../../core/database/tables/profiles.dart';
import 'consistency_calculators.dart';
import 'strength_analytics.dart';

part 'progress_providers.g.dart';

/// Window applied to every chart on the Progress page.
///
/// `null` means all-time — the DAOs take a nullable `since` and omit the
/// lower bound for it, which is what makes imported historical data show up
/// instead of being clipped to a fixed recent window.
/// Windows are *rolling* — "the last 30 days", not "this calendar month" —
/// because [since] is `now - days`. [description] exists so page copy has to
/// state that rather than drifting into calendar language the maths does not
/// implement.
enum ProgressRange {
  month(30, '1M', 'last 30 days', 'the 30 before'),
  quarter(90, '3M', 'last 90 days', 'the 90 before'),
  year(365, '1Y', 'last 12 months', 'the 12 before'),
  all(null, 'All', 'all time', null);

  const ProgressRange(
    this.days,
    this.label,
    this.description,
    this.previousDescription,
  );

  final int? days;
  final String label;

  /// The window in words, e.g. `last 90 days`.
  final String description;

  /// The equal-length window immediately before it, or null for all-time —
  /// which has no preceding window to compare against.
  final String? previousDescription;

  /// Lower bound for the DAO queries, recomputed per read.
  DateTime? get since =>
      days == null ? null : DateTime.now().subtract(Duration(days: days!));
}

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
          since: range.since,
        );

@riverpod
Stream<List<SessionVolumeLoad>> sessionVolumeLoad(
  Ref ref,
  String exerciseId,
  ProgressRange range,
) =>
    ref.watch(workoutDaoProvider).watchSessionVolumeLoad(
          exerciseId,
          since: range.since,
        );

@riverpod
Stream<List<WeeklyVolume>> weeklyVolumeSeries(Ref ref, ProgressRange range) =>
    ref.watch(workoutDaoProvider).watchWeeklyVolume(since: range.since);

@riverpod
Stream<List<WorkoutFrequency>> workoutFrequencySeries(
  Ref ref,
  ProgressRange range,
) =>
    ref.watch(workoutDaoProvider).watchWorkoutFrequency(since: range.since);

@riverpod
Stream<BalanceRatios> balanceRatios(Ref ref, ProgressRange range) =>
    ref.watch(workoutDaoProvider).watchBalanceRatios(since: range.since);

@riverpod
Stream<List<WeeklyMuscleGroupVolume>> weeklyMuscleGroupVolumeSeries(
  Ref ref,
  ProgressRange range,
) =>
    ref
        .watch(workoutDaoProvider)
        .watchWeeklyMuscleGroupVolume(since: range.since);

@riverpod
Stream<List<RepRangeDistribution>> repRangeDistribution(
        Ref ref, ProgressRange range) =>
    ref.watch(workoutDaoProvider).watchRepRangeDistribution(since: range.since);

@riverpod
Stream<List<WeekdayDistribution>> weekdayDistribution(
        Ref ref, ProgressRange range) =>
    ref.watch(workoutDaoProvider).watchWeekdayDistribution(since: range.since);

@riverpod
Future<ConsistencySummary> consistencySummary(
    Ref ref, ProgressRange range) async {
  final weeks = await ref.watch(workoutFrequencySeriesProvider(range).future);
  final Profile? profile = await ref.watch(profileDaoProvider).get();
  return calculateConsistency(
    weeks: weeks,
    targetSessionsPerWeek:
        profile?.weeklySessionTarget ?? defaultWeeklySessionTarget,
  );
}

@riverpod
Stream<List<MuscleGroupVolume>> muscleGroupSeries(
  Ref ref,
  ProgressRange range,
) =>
    ref.watch(workoutDaoProvider).watchMuscleGroupVolume(since: range.since);

/// Body-metric entries inside the selected range.
///
/// Ranged like every other series on the page: the range control sits above
/// all of them and claims to govern all of them, so an all-time body-weight
/// chart under a "1M" selection was simply wrong.
@riverpod
Stream<List<BodyMetrics>> bodyMetricsSeries(Ref ref, ProgressRange range) =>
    ref.watch(bodyMetricsDaoProvider).watchAll(since: range.since);

/// Exercises with logged sets, most-trained first — the 1RM picker's source.
@riverpod
Stream<List<LoggedExercise>> loggedExercises(Ref ref) =>
    ref.watch(workoutDaoProvider).watchLoggedExercises();

@riverpod
Future<List<RelativeStrength>> relativeStrengths(
  Ref ref,
  ProgressRange range,
) async {
  final body = await ref.watch(bodyMetricsDaoProvider).getLatest();
  if (body?.weightKg == null || body!.weightKg <= 0) return const [];
  final measuredAt = body.date;
  if (DateTime.now().difference(measuredAt).inDays > 30) return const [];
  final changes = await ref.watch(strengthChangeProvider(range).future);
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

@riverpod
Future<List<NormalizedLiftSeries>> normalizedLiftSeries(
  Ref ref,
  List<String> exerciseIds,
  ProgressRange range,
) async {
  final dao = ref.watch(workoutDaoProvider);
  final names = {
    for (final exercise in await dao.watchLoggedExercises().first)
      exercise.exerciseId: exercise.exerciseName,
  };
  final result = <NormalizedLiftSeries>[];
  for (final id in exerciseIds.take(3)) {
    final points = await dao.watchOneRMSeries(id, since: range.since).first;
    if (points.isEmpty) continue;
    final ordered = [...points]..sort((a, b) => a.date.compareTo(b.date));
    final start = ordered.first.estimated1RM;
    if (start <= 0) continue;
    result.add(NormalizedLiftSeries(
      exerciseId: id,
      exerciseName: names[id] ?? id,
      points: [
        for (final point in ordered)
          NormalizedPoint(
            date: point.date,
            percentOfStart: point.estimated1RM / start * 100,
          ),
      ],
    ));
  }
  return result;
}

/// Best estimated 1RM per lift in the selected window vs the window before.
///
/// This is the "did I get stronger" series, as opposed to the volume
/// series which answers "how much work did I do".
@riverpod
Stream<List<StrengthChange>> strengthChange(Ref ref, ProgressRange range) =>
    ref.watch(workoutDaoProvider).watchStrengthChange(since: range.since);

/// Best set and prior best for each exercise in one saved workout.
@riverpod
Stream<List<ExercisePerformance>> workoutPerformance(
  Ref ref,
  String workoutId,
) =>
    ref.watch(workoutDaoProvider).watchWorkoutPerformance(workoutId);
