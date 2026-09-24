import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/timer/domain/timer_preset.dart';
import '../services/exercise_seeder.dart';
import 'app_database.dart';
import 'daos/body_metrics_dao.dart';
import 'daos/equipment_dao.dart';
import 'daos/exercise_dao.dart';
import 'daos/muscle_dao.dart';
import 'daos/profile_dao.dart';
import 'daos/program_dao.dart';
import 'daos/template_dao.dart';
import 'daos/timer_dao.dart';
import 'daos/timer_preset_dao.dart';
import 'daos/workout_dao.dart';
import 'tables/equipment.dart';
import 'tables/exercises.dart';
import 'tables/muscles.dart';
import 'tables/workouts.dart';

part 'database_providers.g.dart';

/// The Drift database instance.
///
/// Kept alive — the database is expensive to create and is accessed
/// by nearly every feature provider.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) => AppDatabase();

/// Exercise DAO provider.
@Riverpod(keepAlive: true)
ExerciseDao exerciseDao(Ref ref) => ExerciseDao(ref.watch(appDatabaseProvider));

/// Muscle DAO provider.
@Riverpod(keepAlive: true)
MuscleDao muscleDao(Ref ref) => MuscleDao(ref.watch(appDatabaseProvider));

/// Equipment DAO provider.
@Riverpod(keepAlive: true)
EquipmentDao equipmentDao(Ref ref) =>
    EquipmentDao(ref.watch(appDatabaseProvider));

/// Workout DAO provider.
@Riverpod(keepAlive: true)
WorkoutDao workoutDao(Ref ref) => WorkoutDao(ref.watch(appDatabaseProvider));

/// Template DAO provider.
@Riverpod(keepAlive: true)
TemplateDao templateDao(Ref ref) => TemplateDao(ref.watch(appDatabaseProvider));

/// Program DAO provider.
@Riverpod(keepAlive: true)
ProgramDao programDao(Ref ref) => ProgramDao(ref.watch(appDatabaseProvider));

/// Timer DAO provider.
@Riverpod(keepAlive: true)
TimerDao timerDao(Ref ref) => TimerDao(ref.watch(appDatabaseProvider));

/// Timer preset DAO provider.
@Riverpod(keepAlive: true)
TimerPresetDao timerPresetDao(Ref ref) =>
    TimerPresetDao(ref.watch(appDatabaseProvider));

/// Saved user-created timer presets, oldest first to preserve creation order.
@riverpod
Future<List<TimerPreset>> savedTimerPresets(Ref ref) =>
    ref.watch(timerPresetDaoProvider).getAll();

/// Body metrics DAO provider.
@Riverpod(keepAlive: true)
BodyMetricsDao bodyMetricsDao(Ref ref) =>
    BodyMetricsDao(ref.watch(appDatabaseProvider));

/// Profile DAO provider.
@Riverpod(keepAlive: true)
ProfileDao profileDao(Ref ref) => ProfileDao(ref.watch(appDatabaseProvider));

/// Stream of all exercises (display-ready summaries) — used by Library UI.
@Riverpod(keepAlive: true)
Stream<List<ExerciseSummary>> allExercisesStream(Ref ref) =>
    ref.watch(exerciseSeederProvider.future).asStream().asyncExpand(
          (_) => ref.watch(exerciseDaoProvider).watchAll(),
        );

/// `ExercisesTable.slug` by id, derived from [allExercisesStream].
///
/// Several analytics queries (Progress, Dashboard) denormalize an
/// exercise's English `name` straight into their result rows for display,
/// the same way `ProgramDayExercise` used to — there is no slug to
/// translate by without a second lookup. This is that lookup, built once
/// from the catalogue already being streamed for the Library, rather than
/// adding a slug column to every one of those queries individually.
///
/// A plain derived value, not itself a stream: it recomputes automatically
/// whenever [allExercisesStream] emits, same as any other `ref.watch`
/// dependency, without the extra `AsyncValue` unwrapping a second stream
/// provider would put on every caller.
@Riverpod(keepAlive: true)
Map<String, String> exerciseSlugsById(Ref ref) {
  final List<ExerciseSummary> summaries =
      ref.watch(allExercisesStreamProvider).value ?? const <ExerciseSummary>[];
  return {
    for (final ExerciseSummary summary in summaries)
      summary.exercise.id: summary.exercise.slug,
  };
}

/// Stream of exercises matching a search query (name or alias).
@Riverpod(keepAlive: true)
Stream<List<ExerciseSummary>> exercisesSearchStream(
  Ref ref,
  String query,
) =>
    ref.watch(exerciseSeederProvider.future).asStream().asyncExpand(
          (_) => ref.watch(exerciseDaoProvider).searchByName(query),
        );

/// Stream of exercises filtered by criteria.
@Riverpod(keepAlive: true)
Stream<List<ExerciseSummary>> exercisesFilteredStream(
  Ref ref, {
  String? muscleId,
  String? equipmentId,
  MovementPattern? pattern,
}) =>
    ref.watch(exerciseSeederProvider.future).asStream().asyncExpand(
          (_) => ref.watch(exerciseDaoProvider).filterBy(
                muscleId: muscleId,
                equipmentId: equipmentId,
                pattern: pattern,
              ),
        );

/// The full nested view of one exercise, for the detail sheet.
@riverpod
Future<ExerciseDetail?> exerciseDetail(Ref ref, String exerciseId) async {
  await ref.watch(exerciseSeederProvider.future);
  return ref.watch(exerciseDaoProvider).getWithDetails(exerciseId);
}

/// All muscles — used to build the Library's muscle filter.
@Riverpod(keepAlive: true)
Stream<List<Muscle>> musclesStream(Ref ref) =>
    ref.watch(muscleDaoProvider).watchAll();

/// All equipment — used to build the Library's equipment filter.
@Riverpod(keepAlive: true)
Stream<List<Equipment>> equipmentStream(Ref ref) =>
    ref.watch(equipmentDaoProvider).watchAll();

/// Stream of saved workouts, newest first — used by the Tracker history list.
@Riverpod(keepAlive: true)
Stream<List<Workout>> workoutHistoryStream(Ref ref) =>
    ref.watch(workoutDaoProvider).watchAll();

/// Every saved workout's exercise names, keyed by workout id — used to title
/// the Tracker history rows by what was trained.
@Riverpod(keepAlive: true)
Stream<Map<String, List<WorkoutExerciseName>>> workoutExerciseNames(Ref ref) =>
    ref.watch(workoutDaoProvider).watchExerciseNamesByWorkout();

/// IDs of workouts containing a personal-record set — used to badge the
/// Tracker history list.
@Riverpod(keepAlive: true)
Stream<Set<String>> personalRecordWorkoutIds(Ref ref) =>
    ref.watch(workoutDaoProvider).watchPersonalRecordWorkoutIds();

/// A single workout with its exercises and sets, for the detail/edit screens.
@riverpod
Future<WorkoutWithDetails?> workoutDetail(Ref ref, String workoutId) =>
    ref.watch(workoutDaoProvider).getWithDetails(workoutId);
