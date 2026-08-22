import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/database/daos/workout_dao.dart';
import '../../../core/database/database_providers.dart';
import '../../../core/database/tables/body_metrics.dart';

part 'progress_providers.g.dart';

/// Window applied to every chart on the Progress page.
///
/// `null` means all-time — the DAOs take a nullable `since` and omit the
/// lower bound for it, which is what makes imported historical data show up
/// instead of being clipped to a fixed recent window.
enum ProgressRange {
  month(30, '1M'),
  quarter(90, '3M'),
  year(365, '1Y'),
  all(null, 'All');

  const ProgressRange(this.days, this.label);

  final int? days;
  final String label;

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
Stream<List<WeeklyVolume>> weeklyVolumeSeries(Ref ref, ProgressRange range) =>
    ref.watch(workoutDaoProvider).watchWeeklyVolume(since: range.since);

@riverpod
Stream<List<WorkoutFrequency>> workoutFrequencySeries(
  Ref ref,
  ProgressRange range,
) =>
    ref.watch(workoutDaoProvider).watchWorkoutFrequency(since: range.since);

@riverpod
Stream<List<MuscleGroupVolume>> muscleGroupSeries(
  Ref ref,
  ProgressRange range,
) =>
    ref.watch(workoutDaoProvider).watchMuscleGroupVolume(since: range.since);

@riverpod
Stream<List<BodyMetrics>> bodyMetricsSeries(Ref ref) =>
    ref.watch(bodyMetricsDaoProvider).watchAll();

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
