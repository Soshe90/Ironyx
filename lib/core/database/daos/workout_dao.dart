import 'package:drift/drift.dart';

import '../../formatters/date_formatters.dart';
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
    final Map<String, bool> exerciseIsTimeBased = {};
    for (final row in exerciseRows) {
      final we = row.readTable(workoutExercisesTable);
      exercises.add(WorkoutExercise.fromDrift(we));
      exerciseNames[we.id] = row.readTable(exercisesTable).name;
      exerciseIsTimeBased[we.id] = row.readTable(exercisesTable).isTimeBased;
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
      exerciseIsTimeBased: exerciseIsTimeBased,
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

  /// Average duration of completed workouts, in seconds.
  ///
  /// Incomplete and legacy workouts without a recorded duration are excluded.
  /// The aggregation stays in SQL per ADR-1, and a null result means there is
  /// no duration data to show yet.
  Stream<double?> watchAverageDurationSeconds() => customSelect(
        '''
        SELECT AVG(duration_seconds) AS average_seconds
        FROM workouts_table
        WHERE ended_at IS NOT NULL
          AND duration_seconds IS NOT NULL
          AND duration_seconds > 0
        ''',
        readsFrom: {workoutsTable},
      ).watch().map(
            (rows) => rows.single.read<double?>('average_seconds'),
          );

  /// Weekly volume aggregation — computed in SQL (ADR-1).
  /// Returns (week_start, total_volume_kg) for completed workouts, with
  /// untrained weeks zero-filled — see [_fillWeekGaps].
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
          (rows) => _fillWeekGaps<WeeklyVolume>(
            rows
                .map(
                  (r) => WeeklyVolume(
                    weekStart: DateTime.parse(r.read<String>('week_start')),
                    totalVolumeKg: r.read<double>('total_volume_kg'),
                  ),
                )
                .toList(),
            since: since,
            weekStartOf: (WeeklyVolume w) => w.weekStart,
            zero: (DateTime week) =>
                WeeklyVolume(weekStart: week, totalVolumeKg: 0),
          ),
        );
  }

  /// Workout frequency by week — computed in SQL (ADR-1), with untrained
  /// weeks zero-filled (see [_fillWeekGaps]).
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
          (rows) => _fillWeekGaps<WorkoutFrequency>(
            rows
                .map(
                  (r) => WorkoutFrequency(
                    weekStart: DateTime.parse(r.read<String>('week_start')),
                    workoutCount: r.read<int>('workout_count'),
                  ),
                )
                .toList(),
            since: since,
            weekStartOf: (WorkoutFrequency f) => f.weekStart,
            zero: (DateTime week) =>
                WorkoutFrequency(weekStart: week, workoutCount: 0),
          ),
        );
  }

  /// Emits an explicit zero row for every week in the queried window that
  /// contains no workouts.
  ///
  /// `GROUP BY` produces no row for a week you did not train, so a raw
  /// series silently deletes rest weeks from the x-axis and renders the
  /// weeks either side of a two-month layoff as neighbouring bars. Anything
  /// averaging over the series has the same problem in reverse: dividing by
  /// the row count measures *active* weeks, not elapsed ones, and reports a
  /// single busy week as a sustained rate.
  ///
  /// Filled in Dart rather than with a recursive CTE: the aggregation itself
  /// stays in SQL as ADR-1 requires, and this is presentation-shaped work
  /// (which calendar weeks the window covers) that is far easier to read and
  /// unit-test here.
  ///
  /// The window runs from the first bucket — `since`'s week, or the earliest
  /// row's week for an all-time query — through the current week, so a
  /// window that ends in a layoff shows the layoff. An empty result stays
  /// empty: callers distinguish "never trained" from "trained, then
  /// stopped", and fabricating a run of zeroes would erase that difference.
  List<T> _fillWeekGaps<T>(
    List<T> rows, {
    required DateTime? since,
    required DateTime Function(T) weekStartOf,
    required T Function(DateTime) zero,
  }) {
    if (rows.isEmpty) return rows;

    final Map<DateTime, T> byWeek = <DateTime, T>{
      for (final T row in rows) weekStartOf(row): row,
    };

    DateTime cursor = since == null
        ? weekStartOf(rows.first)
        : DateFormatters.utcWeekStart(since);
    // Rows are ordered ascending, so the last one is the newest. Taking the
    // later of it and the current week keeps a future-dated workout (an
    // import artefact, or a device clock skew) inside the series instead of
    // silently truncating it away.
    final DateTime currentWeek = DateFormatters.utcWeekStart(DateTime.now());
    final DateTime lastWeek = weekStartOf(rows.last);
    final DateTime end = lastWeek.isAfter(currentWeek) ? lastWeek : currentWeek;

    final List<T> filled = <T>[];
    while (!cursor.isAfter(end)) {
      filled.add(byWeek[cursor] ?? zero(cursor));
      cursor = DateFormatters.nextWeek(cursor);
    }
    return filled;
  }

  /// Exercises the user has actually logged, most-sessions first.
  ///
  /// Backs the Progress page's 1RM picker, which previously listed the whole
  /// catalogue — so its default selection was an arbitrary seeded exercise
  /// with no data behind it, and choosing a real lift meant scrolling past
  /// hundreds of entries never performed.
  ///
  /// Filters on the same completed / non-warm-up / loaded / reps-1-12 window
  /// as [watchOneRMSeries], so the picker can never offer a lift whose chart
  /// would then come up empty.
  /// Each saved workout's exercises, in logged order, keyed by workout id —
  /// what the history list names a session by.
  ///
  /// One query for the whole history rather than one per row: the list can
  /// hold years of sessions, and a per-tile lookup would be N+1.
  Stream<Map<String, List<WorkoutExerciseName>>> watchExerciseNamesByWorkout() {
    return customSelect(
      '''
      SELECT we.workout_id AS workout_id,
             we.exercise_id AS exercise_id,
             ex.name AS exercise_name
      FROM workout_exercises_table we
      JOIN exercises_table ex ON ex.id = we.exercise_id
      ORDER BY we.workout_id, we.order_index
      ''',
      readsFrom: {workoutExercisesTable, exercisesTable},
    ).watch().map((rows) {
      final Map<String, List<WorkoutExerciseName>> byWorkout = {};
      for (final r in rows) {
        (byWorkout[r.read<String>('workout_id')] ??= <WorkoutExerciseName>[])
            .add(
          WorkoutExerciseName(
            exerciseId: r.read<String>('exercise_id'),
            exerciseName: r.read<String>('exercise_name'),
          ),
        );
      }
      return byWorkout;
    });
  }

  /// The working sets of [exerciseId] from the most recent finished
  /// workout that has any — what the active workout shows as "last time".
  ///
  /// Null when the exercise has never been completed. Warm-ups are left out
  /// (as a set or as a whole warm-up exercise): they are not the numbers
  /// someone is trying to match. Uses the existing workout_exercises
  /// (exercise_id) index, so it stays cheap as history grows.
  Stream<PreviousPerformance?> watchPreviousPerformance(String exerciseId) {
    return customSelect(
      '''
      SELECT w.started_at AS started_at,
             ws.weight_kg AS weight_kg,
             ws.reps AS reps,
             ws.duration_seconds AS duration_seconds
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
      JOIN workouts_table w ON we.workout_id = w.id
      WHERE we.exercise_id = ?1
        AND ws.is_completed = 1
        AND ws.is_warmup = 0
        AND we.is_warmup = 0
        AND w.id = (
          SELECT w2.id
          FROM workouts_table w2
          JOIN workout_exercises_table we2 ON we2.workout_id = w2.id
          JOIN workout_sets_table ws2 ON ws2.workout_exercise_id = we2.id
          WHERE we2.exercise_id = ?1
            AND w2.ended_at IS NOT NULL
            AND ws2.is_completed = 1
            AND ws2.is_warmup = 0
            AND we2.is_warmup = 0
          ORDER BY w2.started_at DESC
          LIMIT 1
        )
      ORDER BY we.order_index, ws.set_index
      ''',
      variables: [Variable<String>(exerciseId)],
      readsFrom: {workoutSetsTable, workoutExercisesTable, workoutsTable},
    ).watch().map((rows) {
      if (rows.isEmpty) return null;
      return PreviousPerformance(
        date: rows.first.read<DateTime>('started_at'),
        sets: <PreviousSet>[
          for (final r in rows)
            PreviousSet(
              weightKg: r.read<double>('weight_kg'),
              reps: r.read<int>('reps'),
              durationSeconds: r.read<int?>('duration_seconds'),
            ),
        ],
      );
    });
  }

  Stream<List<LoggedExercise>> watchLoggedExercises() {
    return customSelect(
      '''
      SELECT
        we.exercise_id as exercise_id,
        ex.name as exercise_name,
        COUNT(DISTINCT w.id) as session_count
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
      JOIN workouts_table w ON we.workout_id = w.id
      JOIN exercises_table ex ON ex.id = we.exercise_id
      WHERE w.ended_at IS NOT NULL
        AND ws.is_completed = 1
        AND ws.is_warmup = 0
        AND ws.reps BETWEEN 1 AND 12
        AND ws.weight_kg > 0
      GROUP BY we.exercise_id, ex.name
      ORDER BY session_count DESC, ex.name ASC
      ''',
      readsFrom: {
        workoutSetsTable,
        workoutExercisesTable,
        workoutsTable,
        exercisesTable,
      },
    ).watch().map(
          (rows) => rows
              .map(
                (r) => LoggedExercise(
                  exerciseId: r.read<String>('exercise_id'),
                  exerciseName: r.read<String>('exercise_name'),
                  sessionCount: r.read<int>('session_count'),
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
  /// all-time (no lower bound); [until] is an exclusive upper bound used for
  /// comparing a selected range with the preceding range.
  Stream<List<MuscleGroupVolume>> watchMuscleGroupVolume({
    DateTime? since,
    DateTime? until,
  }) {
    final whereSince = since == null ? '' : 'AND w.started_at >= ?';
    final whereUntil = until == null ? '' : 'AND w.started_at < ?';

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
        $whereUntil
      GROUP BY m.id, m.display_name
      HAVING total_volume_kg > 0
      ORDER BY total_volume_kg DESC
      ''',
      variables: [
        if (since != null) Variable.withDateTime(since),
        if (until != null) Variable.withDateTime(until),
      ],
      readsFrom: {
        workoutSetsTable,
        workoutExercisesTable,
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

  /// Session-level RPE and working volume, for fatigue/load comparisons.
  ///
  /// The RPE average covers the sets that carry one; the volume covers the
  /// whole session. Filtering the rows to `rpe_times10 IS NOT NULL` did both
  /// at once, so a session where one set was logged without an RPE reported
  /// a volume lower than the same session's figure everywhere else in the
  /// app. `AVG` already skips nulls, and `HAVING` keeps sessions with no RPE
  /// at all out of the list.
  Stream<List<SessionRpe>> watchRpeAnalytics({DateTime? since}) {
    final sinceClause = since == null ? '' : 'AND w.started_at >= ?';
    return customSelect('''
      SELECT w.id AS workout_id, w.started_at AS date,
        AVG(ws.rpe_times10) AS average_rpe_times_10,
        SUM(ws.weight_kg * ws.reps) AS volume_kg
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON we.id = ws.workout_exercise_id
      JOIN workouts_table w ON w.id = we.workout_id
      WHERE w.ended_at IS NOT NULL AND ws.is_completed = 1
        AND ws.is_warmup = 0 $sinceClause
      GROUP BY w.id, w.started_at
      HAVING COUNT(ws.rpe_times10) > 0
      ORDER BY w.started_at ASC
    ''',
            variables: [if (since != null) Variable.withDateTime(since)],
            readsFrom: {workoutSetsTable, workoutExercisesTable, workoutsTable})
        .watch()
        .map((rows) => [
              for (final row in rows)
                SessionRpe(
                  workoutId: row.read<String>('workout_id'),
                  date: row.read<DateTime>('date'),
                  averageRpe: row.read<double>('average_rpe_times_10') / 10,
                  volumeKg: row.read<double>('volume_kg'),
                ),
            ]);
  }

  /// Per-session average recorded rest between sets.
  Stream<List<SessionRest>> watchRestAnalytics({DateTime? since}) {
    final sinceClause = since == null ? '' : 'AND w.started_at >= ?';
    return customSelect('''
      SELECT w.id AS workout_id, w.started_at AS date,
        AVG(ws.rest_seconds) AS average_rest_seconds,
        COUNT(ws.rest_seconds) AS recorded_rest_count
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON we.id = ws.workout_exercise_id
      JOIN workouts_table w ON w.id = we.workout_id
      WHERE w.ended_at IS NOT NULL AND ws.is_completed = 1
        AND ws.is_warmup = 0 AND ws.rest_seconds IS NOT NULL $sinceClause
      GROUP BY w.id, w.started_at ORDER BY w.started_at ASC
    ''',
            variables: [if (since != null) Variable.withDateTime(since)],
            readsFrom: {workoutSetsTable, workoutExercisesTable, workoutsTable})
        .watch()
        .map((rows) => [
              for (final row in rows)
                SessionRest(
                  workoutId: row.read<String>('workout_id'),
                  date: row.read<DateTime>('date'),
                  averageRestSeconds: row.read<double>('average_rest_seconds'),
                  recordedSetCount: row.read<int>('recorded_rest_count'),
                ),
            ]);
  }

  /// Push/pull and upper/lower volume totals for the selected window.
  Stream<BalanceRatios> watchBalanceRatios({DateTime? since}) {
    final whereSince = since == null ? '' : 'AND w.started_at >= ?';
    return customSelect(
            '''
      SELECT
        COALESCE(SUM(CASE WHEN e.movement_pattern IN ('horizontalPush','verticalPush') THEN ws.weight_kg * ws.reps ELSE 0 END), 0) AS push_volume,
        COALESCE(SUM(CASE WHEN e.movement_pattern IN ('horizontalPull','verticalPull') THEN ws.weight_kg * ws.reps ELSE 0 END), 0) AS pull_volume,
        COALESCE(SUM(CASE WHEN e.movement_pattern IN ('horizontalPush','verticalPush','horizontalPull','verticalPull') THEN ws.weight_kg * ws.reps ELSE 0 END), 0) AS upper_volume,
        COALESCE(SUM(CASE WHEN e.movement_pattern IN ('kneeDominant','hipDominant') THEN ws.weight_kg * ws.reps ELSE 0 END), 0) AS lower_volume
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON we.id = ws.workout_exercise_id
      JOIN workouts_table w ON w.id = we.workout_id
      JOIN exercises_table e ON e.id = we.exercise_id
      WHERE w.ended_at IS NOT NULL AND ws.is_completed = 1 AND ws.is_warmup = 0
      $whereSince
    ''',
            variables: since == null ? [] : [Variable.withDateTime(since)],
            readsFrom: {workoutSetsTable, workoutExercisesTable, workoutsTable, exercisesTable})
        .watchSingle()
        .map((r) => BalanceRatios(
              pushVolumeKg: r.read<double>('push_volume'),
              pullVolumeKg: r.read<double>('pull_volume'),
              upperVolumeKg: r.read<double>('upper_volume'),
              lowerVolumeKg: r.read<double>('lower_volume'),
            ));
  }

  /// Weekly volume attributed to each exercise's primary muscle.
  Stream<List<WeeklyMuscleGroupVolume>> watchWeeklyMuscleGroupVolume(
      {DateTime? since}) {
    final whereSince = since == null ? '' : 'AND w.started_at >= ?';
    return customSelect(
        '''
      SELECT date(w.started_at, 'unixepoch', 'weekday 0', '-6 days') AS week_start,
        m.id AS muscle_id, m.display_name AS muscle_name,
        SUM(ws.weight_kg * ws.reps) AS total_volume_kg
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON we.id = ws.workout_exercise_id
      JOIN workouts_table w ON w.id = we.workout_id
      JOIN exercise_muscles_table em ON em.exercise_id = we.exercise_id AND em.role = 'primary'
      JOIN muscles_table m ON m.id = em.muscle_id
      WHERE w.ended_at IS NOT NULL AND ws.is_completed = 1 AND ws.is_warmup = 0 $whereSince
      GROUP BY week_start, m.id, m.display_name ORDER BY week_start, m.display_name
    ''',
        variables: since == null ? [] : [Variable.withDateTime(since)],
        readsFrom: {
          workoutSetsTable,
          workoutExercisesTable,
          workoutsTable,
          exerciseMusclesTable,
          musclesTable
        }).watch().map((rows) => [
          for (final r in rows)
            WeeklyMuscleGroupVolume(
              weekStart: DateTime.parse(r.read<String>('week_start')),
              muscleId: r.read<String>('muscle_id'),
              muscleName: r.read<String>('muscle_name'),
              totalVolumeKg: r.read<double>('total_volume_kg'),
            ),
        ]);
  }

  /// Working-set exposure split into the three common rep ranges.
  Stream<List<RepRangeDistribution>> watchRepRangeDistribution(
      {DateTime? since}) {
    final whereSince = since == null ? '' : 'AND w.started_at >= ?';
    return customSelect(
            '''
      SELECT CASE WHEN ws.reps BETWEEN 1 AND 5 THEN 'oneToFive'
                  WHEN ws.reps BETWEEN 6 AND 12 THEN 'sixToTwelve'
                  ELSE 'thirteenPlus' END AS rep_range,
        COUNT(*) AS set_count, COALESCE(SUM(ws.weight_kg * ws.reps), 0) AS volume_kg
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON we.id = ws.workout_exercise_id
      JOIN workouts_table w ON w.id = we.workout_id
      WHERE w.ended_at IS NOT NULL AND ws.is_completed = 1 AND ws.is_warmup = 0
        AND ws.reps > 0 $whereSince
      GROUP BY rep_range ORDER BY CASE rep_range WHEN 'oneToFive' THEN 1 WHEN 'sixToTwelve' THEN 2 ELSE 3 END
    ''',
            variables: since == null ? [] : [Variable.withDateTime(since)],
            readsFrom: {workoutSetsTable, workoutExercisesTable, workoutsTable})
        .watch()
        .map((rows) {
      final byRange = {
        for (final range in RepRange.values)
          range: RepRangeDistribution(range: range, setCount: 0, volumeKg: 0)
      };
      for (final r in rows) {
        final range = RepRange.values.byName(r.read<String>('rep_range'));
        byRange[range] = RepRangeDistribution(
            range: range,
            setCount: r.read<int>('set_count'),
            volumeKg: r.read<double>('volume_kg'));
      }
      return [for (final range in RepRange.values) byRange[range]!];
    });
  }

  /// Monday-first distribution of completed workouts and distinct training days.
  ///
  /// Days are resolved in UTC unless [utcOffset] is given: a workout logged
  /// at 00:30 local time in UTC+3 is still the previous UTC day, so a view
  /// that shows *which day* the user trained on passes the device offset.
  /// (DST changes inside the window are ignored — the offset is applied as
  /// one constant, which only matters for workouts within an hour of
  /// midnight on the transition week.)
  Stream<List<WeekdayDistribution>> watchWeekdayDistribution({
    DateTime? since,
    Duration utcOffset = Duration.zero,
  }) {
    final whereSince = since == null ? '' : 'AND started_at >= ?';
    final shifted = 'started_at + ${utcOffset.inSeconds}';
    return customSelect(
        '''
      SELECT CASE CAST(strftime('%w', $shifted, 'unixepoch') AS INTEGER)
               WHEN 0 THEN 7 ELSE CAST(strftime('%w', $shifted, 'unixepoch') AS INTEGER) END AS weekday,
        COUNT(*) AS workout_count,
        COUNT(DISTINCT date($shifted, 'unixepoch')) AS training_day_count
      FROM workouts_table WHERE ended_at IS NOT NULL $whereSince
      GROUP BY weekday ORDER BY weekday
    ''',
        variables: since == null ? [] : [Variable.withDateTime(since)],
        readsFrom: {workoutsTable}).watch().map((rows) {
      final byDay = {
        for (var day = 1; day <= 7; day++)
          day: WeekdayDistribution(
              weekday: day, trainingDayCount: 0, workoutCount: 0)
      };
      for (final r in rows) {
        final day = r.read<int>('weekday');
        byDay[day] = WeekdayDistribution(
            weekday: day,
            trainingDayCount: r.read<int>('training_day_count'),
            workoutCount: r.read<int>('workout_count'));
      }
      return [for (var day = 1; day <= 7; day++) byDay[day]!];
    });
  }

  /// Best estimated 1RM per exercise's most recent session in the window,
  /// next to the best estimate from any session before it.
  ///
  /// This is the "am I getting stronger" query. Volume answers how much
  /// work was done, which moves when you add a set and barely moves when
  /// you add weight — the opposite of what a progress readout needs.
  ///
  /// "Previous" originally meant the equal-length window immediately
  /// before [since] — a comparison that structurally cannot exist unless
  /// the user's training history is at least *twice* the selected range,
  /// so a lift trained only within the last 30 days read "new" under every
  /// range, including the 30-day one. It now means "any earlier qualifying
  /// session for this lift", which needs only a second session to ever
  /// have happened — inside the window or out — and agrees with the old
  /// definition whenever that one already found data. [since] still bounds
  /// which lifts are current enough to list, and `null` (all-time) lists
  /// every lift ever trained; a lift can go from "new" to compared the
  /// moment a second session exists, which — unlike before — now includes
  /// the all-time range too.
  Stream<List<StrengthChange>> watchStrengthChange({DateTime? since}) {
    // Epley, matching watchOneRMSeries and watchPersonalRecordWorkoutIds.
    // Reps are capped at 12 because the estimate degrades badly above it.
    const String oneRm =
        'ws.weight_kg * CASE WHEN ws.reps = 1 THEN 1 ELSE (1 + ws.reps / 30.0) END';
    final String sinceClause = since == null ? '' : 'WHERE started_at >= ?';

    return customSelect(
      '''
      WITH qualifying AS (
        SELECT
          we.exercise_id as exercise_id,
          w.started_at as started_at,
          $oneRm as one_rm
        FROM workout_sets_table ws
        JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
        JOIN workouts_table w ON we.workout_id = w.id
        WHERE w.ended_at IS NOT NULL
          AND ws.is_completed = 1
          AND ws.is_warmup = 0
          AND ws.reps BETWEEN 1 AND 12
          AND ws.weight_kg > 0
      ),
      latest AS (
        SELECT exercise_id, MAX(started_at) as latest_started_at
        FROM qualifying
        $sinceClause
        GROUP BY exercise_id
      )
      SELECT
        l.exercise_id as exercise_id,
        ex.name as exercise_name,
        MAX(CASE WHEN q.started_at = l.latest_started_at
            THEN q.one_rm END) as current_best,
        MAX(CASE WHEN q.started_at < l.latest_started_at
            THEN q.one_rm END) as previous_best
      FROM latest l
      JOIN qualifying q ON q.exercise_id = l.exercise_id
      JOIN exercises_table ex ON ex.id = l.exercise_id
      GROUP BY l.exercise_id, ex.name
      ORDER BY current_best DESC
      ''',
      variables: since == null ? const [] : [Variable.withDateTime(since)],
      readsFrom: {
        workoutSetsTable,
        workoutExercisesTable,
        workoutsTable,
        exercisesTable,
      },
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
          AND ws.weight_kg > 0
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
            AND ws2.weight_kg > 0
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

  /// Per-session load for one lift. This separates heavier lifting from doing
  /// more total work in the same 1RM window.
  ///
  /// Counts *every* completed working set, unlike the 1RM queries. The
  /// reps-1-12 window exists because Epley degrades above it — that is a
  /// property of the estimate, not of the work done, and applying it here
  /// dropped whole sessions off the chart: a 15-rep leg-extension day, or a
  /// 20-rep calf day, simply vanished, so the remaining points read as the
  /// user's entire history for that lift.
  Stream<List<SessionVolumeLoad>> watchSessionVolumeLoad(
    String exerciseId, {
    DateTime? since,
  }) {
    final sinceClause = since == null ? '' : 'AND w.started_at >= ?';
    return customSelect('''
      SELECT w.id AS workout_id, w.started_at AS date,
        SUM(ws.weight_kg * ws.reps) AS volume_kg
      FROM workout_sets_table ws
      JOIN workout_exercises_table we ON we.id = ws.workout_exercise_id
      JOIN workouts_table w ON w.id = we.workout_id
      WHERE we.exercise_id = ? AND w.ended_at IS NOT NULL
        AND ws.is_completed = 1 AND ws.is_warmup = 0 $sinceClause
      GROUP BY w.id, w.started_at ORDER BY w.started_at ASC
    ''', variables: [
      Variable.withString(exerciseId),
      if (since != null) Variable.withDateTime(since),
    ], readsFrom: {
      workoutSetsTable,
      workoutExercisesTable,
      workoutsTable
    }).watch().map((rows) => [
          for (final row in rows)
            SessionVolumeLoad(
              workoutId: row.read<String>('workout_id'),
              date: row.read<DateTime>('date'),
              volumeKg: row.read<double>('volume_kg'),
            ),
        ]);
  }

  /// Per-exercise 1RM series over time (ADR-123): one point per *session*,
  /// its best estimated 1RM that day — not one point per set. A session with
  /// several sets of the same lift would otherwise plot as several points on
  /// the same date, showing intra-workout fatigue instead of a progress
  /// trend, and [limit] would cap the range at N sets rather than N sessions.
  ///
  /// Unloaded sets are excluded along with the reps window: Epley over a
  /// zero external load estimates a 0 kg one-rep max, which plotted push-ups
  /// as a flat zero line and listed them in the strength table at "0 kg".
  /// Bodyweight progress is real but it is not a kilogram figure — every
  /// 1RM-derived query here shares this filter so they cannot disagree.
  Stream<List<OneRMSeriesPoint>> watchOneRMSeries(
    String exerciseId, {
    int limit = 50,
    DateTime? since,
  }) {
    const String oneRm =
        'ws.weight_kg * CASE WHEN ws.reps = 1 THEN 1 ELSE (1 + ws.reps / 30.0) END';

    return customSelect(
      '''
      WITH ranked AS (
        SELECT
          w.started_at as date,
          ws.weight_kg as weight_kg,
          ws.reps as reps,
          ROW_NUMBER() OVER (
            PARTITION BY w.started_at ORDER BY $oneRm DESC
          ) as rank_in_session
        FROM workout_sets_table ws
        JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
        JOIN workouts_table w ON we.workout_id = w.id
        WHERE we.exercise_id = ?
          AND w.ended_at IS NOT NULL
          AND w.started_at >= ?
          AND ws.is_completed = 1
          AND ws.is_warmup = 0
          AND ws.reps BETWEEN 1 AND 12
          AND ws.weight_kg > 0
      )
      SELECT date, weight_kg, reps
      FROM ranked
      WHERE rank_in_session = 1
      ORDER BY date DESC
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
    ).watch().map((rows) {
      final points = rows.map((r) {
        final weightKg = r.read<double>('weight_kg');
        final reps = r.read<int>('reps');
        final date = r.read<DateTime>('date');
        final oneRM = reps == 1 ? weightKg : weightKg * (1 + reps / 30.0);
        return OneRMSeriesPoint(date: date, estimated1RM: oneRM);
      }).toList();
      // The query is newest-first. Mark points against earlier points in the
      // returned window, then restore newest-first order for existing callers.
      var best = double.negativeInfinity;
      for (final point in points.reversed) {
        final isRecord = point.estimated1RM > best;
        if (isRecord) best = point.estimated1RM;
        final index = points.indexOf(point);
        points[index] = OneRMSeriesPoint(
          date: point.date,
          estimated1RM: point.estimated1RM,
          isPersonalRecord: isRecord,
        );
      }
      return points;
    });
  }

  /// IDs of workouts that set at least one personal record — i.e. contain a
  /// completed, non-warmup set whose estimated 1RM beats every same-exercise
  /// set from a strictly earlier workout. Computed in SQL (ADR-1) so the
  /// history list can badge entries without loading every set into Dart.
  ///
  /// Mirrors the same reps-1-12 estimation window as [watchOneRMSeries] and
  /// the same Epley formula as [isPersonalRecord] in `progress_calculators`,
  /// so a badge here always agrees with the 1RM chart.
  Stream<Set<String>> watchPersonalRecordWorkoutIds({DateTime? since}) {
    const String oneRm =
        'ws.weight_kg * CASE WHEN ws.reps = 1 THEN 1 ELSE (1 + ws.reps / 30.0) END';

    // A workout counts as a PR for an exercise if *any* of its sets beats
    // every strictly-earlier workout's best for that exercise — which is
    // the same thing as its *best* set beating that history, since "some
    // set beats X" iff "the best set beats X". Aggregating to one row per
    // (workout, exercise) first and comparing with a window function is
    // O(n log n); the previous correlated subquery re-scanned the sets
    // table once per outer *set* row, which was O(n^2) and took over 100
    // seconds against a benchmark of 3,000 workouts / 36,000 sets — this
    // powers a PR badge on every workout in history, so at that scale the
    // list would have simply hung.
    return customSelect(
      '''
      WITH workout_best AS (
        SELECT
          w.id AS workout_id,
          we.exercise_id AS exercise_id,
          w.started_at AS started_at,
          MAX($oneRm) AS best_one_rm
        FROM workout_sets_table ws
        JOIN workout_exercises_table we ON ws.workout_exercise_id = we.id
        JOIN workouts_table w ON we.workout_id = w.id
        WHERE w.ended_at IS NOT NULL
          AND ws.is_completed = 1
          AND ws.is_warmup = 0
          AND ws.reps BETWEEN 1 AND 12
          AND ws.weight_kg > 0
        GROUP BY w.id, we.exercise_id
      ),
      scored AS (
        SELECT
          workout_id,
          started_at,
          best_one_rm,
          MAX(best_one_rm) OVER (
            PARTITION BY exercise_id ORDER BY started_at
            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
          ) AS prior_best
        FROM workout_best
      )
      SELECT DISTINCT workout_id
      FROM scored
      WHERE best_one_rm > COALESCE(prior_best, 0)
        ${since == null ? '' : 'AND started_at >= ?'}
      ''',
      variables: since == null ? [] : [Variable.withDateTime(since)],
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
          AND ws.weight_kg > 0
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
          AND ws.weight_kg > 0
        GROUP BY w.id, w.started_at
      )
      SELECT
        (SELECT exercise_id FROM set_counts) AS exercise_id,
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
      final String exerciseId = rows.first.read<String>('exercise_id');
      final String exerciseName = rows.first.read<String>('exercise_name');
      final double currentKg = rows.first.read<double>('best_1rm');
      final double? previousKg =
          rows.length > 1 ? rows[1].read<double>('best_1rm') : null;
      return MostLoggedOneRM(
        exerciseId: exerciseId,
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

  /// Null when there is no earlier qualifying session for this lift at
  /// all — it was first trained inside the current window, or has only
  /// ever been trained once. A new lift is not a regression, so callers
  /// must not treat null as zero.
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

/// An exercise's working sets from its most recent finished session.
class PreviousPerformance {
  const PreviousPerformance({required this.date, required this.sets});

  final DateTime date;
  final List<PreviousSet> sets;
}

class PreviousSet {
  const PreviousSet({
    required this.weightKg,
    required this.reps,
    this.durationSeconds,
  });

  final double weightKg;
  final int reps;
  final int? durationSeconds;
}

/// One exercise of a saved workout, for naming the session in history.
class WorkoutExerciseName {
  const WorkoutExerciseName({
    required this.exerciseId,
    required this.exerciseName,
  });

  final String exerciseId;
  final String exerciseName;
}

/// An exercise the user has logged, with how many sessions it appears in.
class LoggedExercise {
  const LoggedExercise({
    required this.exerciseId,
    required this.exerciseName,
    required this.sessionCount,
  });

  final String exerciseId;
  final String exerciseName;
  final int sessionCount;
}

class BalanceRatios {
  const BalanceRatios(
      {required this.pushVolumeKg,
      required this.pullVolumeKg,
      required this.upperVolumeKg,
      required this.lowerVolumeKg});
  final double pushVolumeKg;
  final double pullVolumeKg;
  final double upperVolumeKg;
  final double lowerVolumeKg;
  double? get pushPullRatio =>
      pullVolumeKg == 0 ? null : pushVolumeKg / pullVolumeKg;
  double? get upperLowerRatio =>
      lowerVolumeKg == 0 ? null : upperVolumeKg / lowerVolumeKg;
}

class WeeklyMuscleGroupVolume {
  const WeeklyMuscleGroupVolume(
      {required this.weekStart,
      required this.muscleId,
      required this.muscleName,
      required this.totalVolumeKg});
  final DateTime weekStart;
  final String muscleId;
  final String muscleName;
  final double totalVolumeKg;
}

enum RepRange { oneToFive, sixToTwelve, thirteenPlus }

class RepRangeDistribution {
  const RepRangeDistribution(
      {required this.range, required this.setCount, required this.volumeKg});
  final RepRange range;
  final int setCount;
  final double volumeKg;
}

class WeekdayDistribution {
  const WeekdayDistribution(
      {required this.weekday,
      required this.trainingDayCount,
      required this.workoutCount});
  final int weekday;
  final int trainingDayCount;
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
class SessionRpe {
  const SessionRpe(
      {required this.workoutId,
      required this.date,
      required this.averageRpe,
      required this.volumeKg});
  final String workoutId;
  final DateTime date;
  final double averageRpe;
  final double volumeKg;
}

class SessionRest {
  const SessionRest(
      {required this.workoutId,
      required this.date,
      required this.averageRestSeconds,
      required this.recordedSetCount});
  final String workoutId;
  final DateTime date;
  final double averageRestSeconds;
  final int recordedSetCount;
}

class SessionVolumeLoad {
  const SessionVolumeLoad(
      {required this.workoutId, required this.date, required this.volumeKg});
  final String workoutId;
  final DateTime date;
  final double volumeKg;
}

class OneRMSeriesPoint {
  const OneRMSeriesPoint(
      {required this.date,
      required this.estimated1RM,
      this.isPersonalRecord = false});

  final DateTime date;
  final double estimated1RM;
  final bool isPersonalRecord;
}

/// Direction of change between a lift's most recent two 1RM estimates.
enum OneRMTrend { up, down, flat }

/// Est. 1RM for the most-logged exercise, for the Progress dashboard card.
class MostLoggedOneRM {
  const MostLoggedOneRM({
    required this.exerciseId,
    required this.exerciseName,
    required this.currentKg,
    required this.trend,
  });

  final String exerciseId;
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
    required this.exerciseIsTimeBased,
    required this.setsByExercise,
  });

  final Workout workout;
  final List<WorkoutExercise> exercises;

  /// Exercise display name keyed by [WorkoutExercise.id] (not exerciseId).
  final Map<String, String> exerciseNames;

  /// Whether the exercise logs a held duration instead of reps, keyed by
  /// [WorkoutExercise.id] (not exerciseId).
  final Map<String, bool> exerciseIsTimeBased;
  final Map<String, List<WorkoutSet>> setsByExercise;
}
