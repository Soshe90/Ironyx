import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/exercise_muscles.dart';
import '../tables/exercises.dart';
import '../tables/muscles.dart';
import '../tables/workout_exercises.dart';
import '../tables/workout_sets.dart';
import '../tables/workouts.dart';

part 'workout_dao.g.dart';

@DriftAccessor(
  tables: [
    WorkoutsTable,
    WorkoutExercisesTable,
    WorkoutSetsTable,
    ExercisesTable,
    ExerciseMusclesTable,
    MusclesTable,
  ],
)
class WorkoutDao extends DatabaseAccessor<AppDatabase> with _$WorkoutDaoMixin {
  WorkoutDao(super.db);

  /// Watch all workouts, newest first.
  Stream<List<Workout>> watchAll({int? limit}) {
    final query = select(workoutsTable)
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]);
    if (limit != null) query.limit(limit);
    return query.watch().map(
          (rows) => rows.map<Workout>(Workout.fromDrift).toList(),
        );
  }

  /// Get a single workout by ID with exercises, sets, and exercise names.
  Future<WorkoutWithDetails?> getWithDetails(String workoutId) async {
    final workout = await (select(
      workoutsTable,
    )..where((t) => t.id.equals(workoutId)))
        .getSingleOrNull();
    if (workout == null) return null;

    final exerciseRows = await (select(workoutExercisesTable).join([
      innerJoin(
        exercisesTable,
        exercisesTable.id.equalsExp(workoutExercisesTable.exerciseId),
      ),
    ])
          ..where(workoutExercisesTable.workoutId.equals(workoutId))
          ..orderBy([OrderingTerm.asc(workoutExercisesTable.orderIndex)]))
        .get();

    final exercises = <WorkoutExercise>[];
    final Map<String, String> exerciseNames = {};
    for (final row in exerciseRows) {
      final we = row.readTable(workoutExercisesTable);
      exercises.add(WorkoutExercise.fromDrift(we));
      exerciseNames[we.id] = row.readTable(exercisesTable).name;
    }

    final Map<String, List<WorkoutSet>> setsByExercise = {};
    for (final ex in exercises) {
      final sets = await (select(workoutSetsTable)
            ..where((t) => t.workoutExerciseId.equals(ex.id))
            ..orderBy([(t) => OrderingTerm.asc(t.setIndex)]))
          .get();
      setsByExercise[ex.id] =
          sets.map<WorkoutSet>(WorkoutSet.fromDrift).toList();
    }

    return WorkoutWithDetails(
      workout: Workout.fromDrift(workout),
      exercises: exercises,
      exerciseNames: exerciseNames,
      setsByExercise: setsByExercise,
    );
  }

  /// Delete a workout. Cascades to its exercises and sets (ADR: FK cascade).
  Future<void> deleteWorkout(String workoutId) =>
      (delete(workoutsTable)..where((t) => t.id.equals(workoutId))).go();

  /// Replace a workout's exercises and sets, and update its total volume.
  ///
  /// Used by the edit flow — `startedAt`/`endedAt` are left untouched.
  Future<void> updateWorkout({
    required String workoutId,
    required double totalVolumeKg,
    required List<WorkoutExercisesTableCompanion> exercises,
    required List<WorkoutSetsTableCompanion> sets,
  }) {
    return transaction(() async {
      await (delete(
        workoutExercisesTable,
      )..where((t) => t.workoutId.equals(workoutId)))
          .go();
      await batch((b) => b.insertAll(workoutExercisesTable, exercises));
      await batch((b) => b.insertAll(workoutSetsTable, sets));
      await (update(workoutsTable)..where((t) => t.id.equals(workoutId)))
          .write(WorkoutsTableCompanion(totalVolumeKg: Value(totalVolumeKg)));
    });
  }

  /// Get workouts in a date range (for weekly volume, etc.).
  Stream<List<Workout>> watchInRange(DateTime start, DateTime end) =>
      (select(workoutsTable)
            ..where((t) => t.startedAt.isBetweenValues(start, end))
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)]))
          .watch()
          .map((rows) => rows.map<Workout>(Workout.fromDrift).toList());

  /// Weekly volume aggregation — computed in SQL (ADR-1).
  /// Returns (week_start, total_volume_kg) for completed workouts.
  /// `since` is null for all-time (no lower bound).
  Stream<List<WeeklyVolume>> watchWeeklyVolume({DateTime? since}) {
    final whereSince = since == null ? '' : 'AND started_at >= ?';

    return customSelect(
      '''
      SELECT
        date(started_at, 'unixepoch', 'weekday 0', '-6 days') as week_start,
        SUM(total_volume_kg) as total_volume_kg
      FROM workouts_table
      WHERE ended_at IS NOT NULL
        $whereSince
      GROUP BY week_start
      ORDER BY week_start ASC
      ''',
      variables: since == null ? [] : [Variable.withDateTime(since)],
      readsFrom: {workoutsTable},
    ).watch().map(
          (rows) => rows
              .map(
                (r) => WeeklyVolume(
                  weekStart: DateTime.parse(r.read<String>('week_start')),
                  totalVolumeKg: r.read<double>('total_volume_kg'),
                ),
              )
              .toList(),
        );
  }

  /// Workout frequency by week — computed in SQL (ADR-1).
  /// `since` is null for all-time (no lower bound).
  Stream<List<WorkoutFrequency>> watchWorkoutFrequency({DateTime? since}) {
    final whereSince = since == null ? '' : 'AND started_at >= ?';

    return customSelect(
      '''
      SELECT
        date(started_at, 'unixepoch', 'weekday 0', '-6 days') as week_start,
        COUNT(*) as workout_count
      FROM workouts_table
      WHERE ended_at IS NOT NULL
        $whereSince
      GROUP BY week_start
      ORDER BY week_start ASC
      ''',
      variables: since == null ? [] : [Variable.withDateTime(since)],
      readsFrom: {workoutsTable},
    ).watch().map(
          (rows) => rows
              .map(
                (r) => WorkoutFrequency(
                  weekStart: DateTime.parse(r.read<String>('week_start')),
                  workoutCount: r.read<int>('workout_count'),
                ),
              )
              .toList(),
        );
  }

  /// Volume by muscle group over a window — computed in SQL (ADR-1).
  ///
  /// Attributes each set's volume to its exercise's *primary* muscle only,
  /// so a set is never double-counted across secondary/stabilizer roles.
  /// Returns groups ordered by volume descending. `since` is null for
  /// all-time (no lower bound).
  Stream<List<MuscleGroupVolume>> watchMuscleGroupVolume({DateTime? since}) {
    final whereSince = since == null ? '' : 'AND w.started_at >= ?';

    return customSelect(
      '''
      SELECT
        m.id as muscle_id,
        m.display_name as muscle_name,
        SUM(ws.weight_kg * ws.reps) as total_volume_kg
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
      JOIN workouts_table w ON we.workout_id = w.id
      JOIN exercise_muscles_table em
        ON em.exercise_id = we.exercise_id AND em.role = 'primary'
      JOIN muscles_table m ON m.id = em.muscle_id
      WHERE w.ended_at IS NOT NULL
        AND ws.is_completed = 1
        AND ws.is_warmup = 0
        $whereSince
      GROUP BY m.id, m.display_name
      HAVING total_volume_kg > 0
      ORDER BY total_volume_kg DESC
      ''',
      variables: since == null ? [] : [Variable.withDateTime(since)],
      readsFrom: {
        workoutSetsTable,
        workoutExercisesTable,
        workoutsTable,
        exerciseMusclesTable,
        musclesTable,
      },
    ).watch().map(
          (rows) => rows
              .map(
                (r) => MuscleGroupVolume(
                  muscleId: r.read<String>('muscle_id'),
                  muscleName: r.read<String>('muscle_name'),
                  totalVolumeKg: r.read<double>('total_volume_kg'),
                ),
              )
              .toList(),
        );
  }

  /// Best estimated 1RM per exercise in a window, next to the same figure
  /// for the window immediately before it.
  ///
  /// This is the "am I getting stronger" query. Volume answers how much
  /// work was done, which moves when you add a set and barely moves when
  /// you add weight — the opposite of what a progress readout needs.
  ///
  /// [since] null means all-time, in which case there is no preceding
  /// window and [StrengthChange.previousBestKg] is null for every row.
  Stream<List<StrengthChange>> watchStrengthChange({DateTime? since}) {
    // The preceding window of equal length: [since - len, since).
    final DateTime? previousSince =
        since?.subtract(DateTime.now().difference(since));

    // Epley, matching watchOneRMSeries and watchPersonalRecordWorkoutIds.
    // Reps are capped at 12 because the estimate degrades badly above it.
    const String oneRm =
        'ws.weight_kg * CASE WHEN ws.reps = 1 THEN 1 ELSE (1 + ws.reps / 30.0) END';

    // Indexed placeholders (?1 current-window start, ?2 previous-window
    // start) because each is referenced more than once; drift binds the
    // `variables` list positionally.
    final String currentCase =
        since == null ? oneRm : 'CASE WHEN w.started_at >= ?1 THEN $oneRm END';
    final String previousCase = since == null
        ? 'NULL'
        : 'CASE WHEN w.started_at >= ?2 AND w.started_at < ?1 '
            'THEN $oneRm END';
    final String lowerBound = since == null ? '' : 'AND w.started_at >= ?2';

    return customSelect(
      '''
      SELECT
        we.exercise_id as exercise_id,
        ex.name as exercise_name,
        MAX($currentCase) as current_best,
        MAX($previousCase) as previous_best
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
      JOIN workouts_table w ON we.workout_id = w.id
      JOIN exercises_table ex ON ex.id = we.exercise_id
      WHERE w.ended_at IS NOT NULL
        AND ws.is_completed = 1
        AND ws.is_warmup = 0
        AND ws.reps BETWEEN 1 AND 12
        $lowerBound
      GROUP BY we.exercise_id, ex.name
      HAVING current_best IS NOT NULL
      ORDER BY current_best DESC
      ''',
      variables: since == null
          ? const []
          : [
              Variable.withDateTime(since),
              Variable.withDateTime(previousSince!),
            ],
      readsFrom: {workoutSetsTable, workoutExercisesTable, workoutsTable},
    ).watch().map(
          (rows) => rows
              .map(
                (r) => StrengthChange(
                  exerciseId: r.read<String>('exercise_id'),
                  exerciseName: r.read<String>('exercise_name'),
                  currentBestKg: r.read<double>('current_best'),
                  previousBestKg: r.readNullable<double>('previous_best'),
                ),
              )
              .toList(),
        );
  }

  /// For one workout: each exercise's best set, its estimated 1RM, and the
  /// best 1RM that lift had reached *before* this workout.
  ///
  /// Lets the detail screen say "Leg Press, 55 lb x 10, +9% on your
  /// previous best" instead of a volume figure that cannot be compared to
  /// anything.
  Stream<List<ExercisePerformance>> watchWorkoutPerformance(String workoutId) {
    const String oneRm =
        'ws.weight_kg * CASE WHEN ws.reps = 1 THEN 1 ELSE (1 + ws.reps / 30.0) END';

    // Ranks the sets explicitly rather than leaning on SQLite's
    // "bare columns take the MAX row" behaviour: that only holds when the
    // query contains exactly one min/max aggregate, so merely adding an
    // ORDER BY MIN(...) silently made it return the *first* set instead of
    // the best one. A window function states the intent and cannot drift.
    return customSelect(
      '''
      WITH ranked AS (
        SELECT
          we.exercise_id as exercise_id,
          we.order_index as order_index,
          ws.weight_kg as weight_kg,
          ws.reps as reps,
          $oneRm as one_rm,
          ROW_NUMBER() OVER (
            PARTITION BY we.exercise_id ORDER BY $oneRm DESC
          ) as rank_in_exercise
        FROM workout_sets_table ws
        JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
        WHERE we.workout_id = ?1
          AND ws.is_completed = 1
          AND ws.is_warmup = 0
          AND ws.reps BETWEEN 1 AND 12
      )
      SELECT
        r.exercise_id as exercise_id,
        ex.name as exercise_name,
        r.weight_kg as weight_kg,
        r.reps as reps,
        r.one_rm as one_rm,
        (
          SELECT MAX(
            ws2.weight_kg * CASE WHEN ws2.reps = 1 THEN 1
                                 ELSE (1 + ws2.reps / 30.0) END
          )
          FROM workout_sets_table ws2
          JOIN workout_exercises_table we2
            ON ws2.workout_exercise_id = we2.id
          JOIN workouts_table w2 ON we2.workout_id = w2.id
          WHERE we2.exercise_id = r.exercise_id
            AND w2.ended_at IS NOT NULL
            AND ws2.is_completed = 1
            AND ws2.is_warmup = 0
            AND ws2.reps BETWEEN 1 AND 12
            AND w2.started_at < (
              SELECT started_at FROM workouts_table WHERE id = ?1
            )
        ) as previous_best
      FROM ranked r
      JOIN exercises_table ex ON ex.id = r.exercise_id
      WHERE r.rank_in_exercise = 1
      ORDER BY r.order_index
      ''',
      variables: [Variable.withString(workoutId)],
      readsFrom: {workoutSetsTable, workoutExercisesTable, workoutsTable},
    ).watch().map(
          (rows) => rows
              .map(
                (r) => ExercisePerformance(
                  exerciseId: r.read<String>('exercise_id'),
                  exerciseName: r.read<String>('exercise_name'),
                  bestWeightKg: r.read<double>('weight_kg'),
                  bestReps: r.read<int>('reps'),
                  bestOneRmKg: r.read<double>('one_rm'),
                  previousBestKg: r.readNullable<double>('previous_best'),
                ),
              )
              .toList(),
        );
  }

  /// Per-exercise 1RM series over time (ADR-123).
  /// Returns (date, exercise_id, estimated_1rm_kg) for completed, non-warmup sets.
  Stream<List<OneRMSeriesPoint>> watchOneRMSeries(
    String exerciseId, {
    int limit = 50,
    DateTime? since,
  }) {
    return customSelect(
      '''
      SELECT
        w.started_at as date,
        ws.weight_kg,
        ws.reps
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
      JOIN workouts_table w ON we.workout_id = w.id
      WHERE we.exercise_id = ?
        AND w.ended_at IS NOT NULL
        AND w.started_at >= ?
        AND ws.is_completed = 1
        AND ws.is_warmup = 0
        AND ws.reps BETWEEN 1 AND 12
      ORDER BY w.started_at DESC
      LIMIT ?
      ''',
      variables: [
        Variable.withString(exerciseId),
        Variable.withDateTime(
          since ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ),
        Variable.withInt(limit),
      ],
      readsFrom: {workoutSetsTable, workoutExercisesTable, workoutsTable},
    ).watch().map(
          (rows) => rows.map((r) {
            final weightKg = r.read<double>('weight_kg');
            final reps = r.read<int>('reps');
            // `date` is a raw `started_at` passthrough (not a SQL date()
            // call), so it's still in the column's native storage
            // representation — read it typed as DateTime rather than
            // parsing it as an ISO string.
            final date = r.read<DateTime>('date');
            final oneRM = reps == 1 ? weightKg : weightKg * (1 + reps / 30.0);
            return OneRMSeriesPoint(date: date, estimated1RM: oneRM);
          }).toList(),
        );
  }

  /// IDs of workouts that set at least one personal record — i.e. contain a
  /// completed, non-warmup set whose estimated 1RM beats every same-exercise
  /// set from a strictly earlier workout. Computed in SQL (ADR-1) so the
  /// history list can badge entries without loading every set into Dart.
  ///
  /// Mirrors the same reps-1-12 estimation window as [watchOneRMSeries] and
  /// the same Epley formula as [isPersonalRecord] in `progress_calculators`,
  /// so a badge here always agrees with the 1RM chart.
  Stream<Set<String>> watchPersonalRecordWorkoutIds() {
    return customSelect(
      '''
      SELECT DISTINCT w.id as workout_id
      FROM workouts_table w
      JOIN workout_exercises_table we ON we.workout_id = w.id
      JOIN workout_sets_table ws ON ws.workout_exercise_id = we.id
      WHERE w.ended_at IS NOT NULL
        AND ws.is_completed = 1
        AND ws.is_warmup = 0
        AND ws.reps BETWEEN 1 AND 12
        AND (ws.weight_kg * CASE WHEN ws.reps = 1 THEN 1 ELSE (1 + ws.reps / 30.0) END) > (
          SELECT COALESCE(MAX(
            ws2.weight_kg * CASE WHEN ws2.reps = 1 THEN 1 ELSE (1 + ws2.reps / 30.0) END
          ), 0)
          FROM workout_sets_table ws2
          JOIN workout_exercises_table we2 ON ws2.workout_exercise_id = we2.id
          JOIN workouts_table w2 ON we2.workout_id = w2.id
          WHERE we2.exercise_id = we.exercise_id
            AND w2.ended_at IS NOT NULL
            AND ws2.is_completed = 1
            AND ws2.is_warmup = 0
            AND ws2.reps BETWEEN 1 AND 12
            AND w2.started_at < w.started_at
        )
      ''',
      readsFrom: {workoutsTable, workoutExercisesTable, workoutSetsTable},
    ).watch().map(
          (rows) => rows.map((r) => r.read<String>('workout_id')).toSet(),
        );
  }

  /// Est. 1RM and trend for the Progress dashboard card: the exercise with
  /// the most logged sets overall, its most recent workout's best estimated
  /// 1RM, and whether that beats the workout before it. Same Epley formula
  /// and reps-1-12 estimation window as [watchOneRMSeries].
  Stream<MostLoggedOneRM?> watchMostLoggedExerciseOneRM() {
    return customSelect(
      '''
      WITH set_counts AS (
        SELECT we.exercise_id AS exercise_id, COUNT(*) AS set_count
        FROM workout_sets_table ws
        JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
        JOIN workouts_table w ON we.workout_id = w.id
        WHERE ws.is_completed = 1
          AND ws.is_warmup = 0
          AND w.ended_at IS NOT NULL
          AND ws.reps BETWEEN 1 AND 12
        GROUP BY we.exercise_id
        ORDER BY set_count DESC
        LIMIT 1
      ),
      per_workout AS (
        SELECT
          w.started_at AS started_at,
          MAX(
            CASE WHEN ws.reps = 1 THEN ws.weight_kg
                 ELSE ws.weight_kg * (1 + ws.reps / 30.0) END
          ) AS best_1rm
        FROM workout_sets_table ws
        JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
        JOIN workouts_table w ON we.workout_id = w.id
        WHERE we.exercise_id = (SELECT exercise_id FROM set_counts)
          AND ws.is_completed = 1
          AND ws.is_warmup = 0
          AND w.ended_at IS NOT NULL
          AND ws.reps BETWEEN 1 AND 12
        GROUP BY w.id, w.started_at
      )
      SELECT
        (SELECT name FROM exercises_table
          WHERE id = (SELECT exercise_id FROM set_counts)) AS exercise_name,
        best_1rm
      FROM per_workout
      ORDER BY started_at DESC
      LIMIT 2
      ''',
      readsFrom: {
        workoutSetsTable,
        workoutExercisesTable,
        workoutsTable,
        exercisesTable,
      },
    ).watch().map((rows) {
      if (rows.isEmpty) return null;
      final String exerciseName = rows.first.read<String>('exercise_name');
      final double currentKg = rows.first.read<double>('best_1rm');
      final double? previousKg =
          rows.length > 1 ? rows[1].read<double>('best_1rm') : null;
      return MostLoggedOneRM(
        exerciseName: exerciseName,
        currentKg: currentKg,
        trend: previousKg == null
            ? OneRMTrend.flat
            : currentKg > previousKg
                ? OneRMTrend.up
                : currentKg < previousKg
                    ? OneRMTrend.down
                    : OneRMTrend.flat,
      );
    });
  }

  /// Insert a completed workout with exercises and sets in a transaction.
  Future<String> insertWorkout(
    WorkoutsTableCompanion workout,
    List<WorkoutExercisesTableCompanion> exercises,
    List<WorkoutSetsTableCompanion> sets,
  ) {
    return transaction(() async {
      await into(workoutsTable).insert(workout);
      await batch((b) => b.insertAll(workoutExercisesTable, exercises));
      await batch((b) => b.insertAll(workoutSetsTable, sets));
      return workout.id.value;
    });
  }
}

/// Weekly volume data point.
/// One exercise's best set within a workout, against its prior best.
class ExercisePerformance {
  const ExercisePerformance({
    required this.exerciseId,
    required this.exerciseName,
    required this.bestWeightKg,
    required this.bestReps,
    required this.bestOneRmKg,
    required this.previousBestKg,
  });

  final String exerciseId;
  final String exerciseName;
  final double bestWeightKg;
  final int bestReps;
  final double bestOneRmKg;

  /// Best 1RM for this lift before this workout. Null the first time the
  /// lift was performed — which is not a regression.
  final double? previousBestKg;

  bool get isFirstTime => previousBestKg == null;

  bool get isPersonalRecord =>
      previousBestKg != null && bestOneRmKg > previousBestKg!;

  /// Fractional change against the prior best, null on a first attempt.
  double? get change {
    final double? previous = previousBestKg;
    if (previous == null || previous == 0) return null;
    return (bestOneRmKg - previous) / previous;
  }
}

/// One lift's best estimated 1RM in a window, against the window before.
class StrengthChange {
  const StrengthChange({
    required this.exerciseId,
    required this.exerciseName,
    required this.currentBestKg,
    required this.previousBestKg,
  });

  final String exerciseId;
  final String exerciseName;
  final double currentBestKg;

  /// Null when there is nothing to compare against — either the range is
  /// all-time, or the lift is new this window. A new lift is not a
  /// regression, so callers must not treat null as zero.
  final double? previousBestKg;

  bool get isNew => previousBestKg == null;

  /// Fractional change, e.g. 0.09 for +9%. Null when [isNew].
  double? get change {
    final double? previous = previousBestKg;
    if (previous == null || previous == 0) return null;
    return (currentBestKg - previous) / previous;
  }
}

class WeeklyVolume {
  const WeeklyVolume({required this.weekStart, required this.totalVolumeKg});

  final DateTime weekStart;
  final double totalVolumeKg;
}

/// Completed workout count attributed to one week.
class WorkoutFrequency {
  const WorkoutFrequency({
    required this.weekStart,
    required this.workoutCount,
  });

  final DateTime weekStart;
  final int workoutCount;
}

/// Total training volume attributed to one muscle group over a window.
class MuscleGroupVolume {
  const MuscleGroupVolume({
    required this.muscleId,
    required this.muscleName,
    required this.totalVolumeKg,
  });

  final String muscleId;
  final String muscleName;
  final double totalVolumeKg;
}

/// OneRM series data point.
class OneRMSeriesPoint {
  const OneRMSeriesPoint({required this.date, required this.estimated1RM});

  final DateTime date;
  final double estimated1RM;
}

/// Direction of change between a lift's most recent two 1RM estimates.
enum OneRMTrend { up, down, flat }

/// Est. 1RM for the most-logged exercise, for the Progress dashboard card.
class MostLoggedOneRM {
  const MostLoggedOneRM({
    required this.exerciseName,
    required this.currentKg,
    required this.trend,
  });

  final String exerciseName;
  final double currentKg;
  final OneRMTrend trend;
}

/// Workout with nested exercises and sets.
class WorkoutWithDetails {
  const WorkoutWithDetails({
    required this.workout,
    required this.exercises,
    required this.exerciseNames,
    required this.setsByExercise,
  });

  final Workout workout;
  final List<WorkoutExercise> exercises;

  /// Exercise display name keyed by [WorkoutExercise.id] (not exerciseId).
  final Map<String, String> exerciseNames;
  final Map<String, List<WorkoutSet>> setsByExercise;
}
