import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';

void main() {
  late AppDatabase database;
  late WorkoutDao workoutDao;
  late ExerciseDao exerciseDao;

  setUp(() async {
    database = AppDatabase.forTesting();
    workoutDao = WorkoutDao(database);
    exerciseDao = ExerciseDao(database);
    await exerciseDao.upsertExercises([
      ExercisesTableCompanion.insert(
        id: 'squat',
        slug: 'squat',
        name: 'Back Squat',
        category: 'strength',
        difficulty: 'intermediate',
        movementPattern: 'kneeDominant',
        isBodyweight: const Value(false),
        seedVersion: 1,
      ),
    ]);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> insertSampleWorkout(
    String workoutId, {
    DateTime? startedAt,
  }) {
    final start = startedAt ?? DateTime.utc(2026, 1, 1);
    return workoutDao.insertWorkout(
      WorkoutsTableCompanion.insert(
        id: workoutId,
        startedAt: start,
        endedAt: Value(start.add(const Duration(hours: 1))),
        totalVolumeKg: const Value(500),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: '${workoutId}_ex1',
          workoutId: workoutId,
          exerciseId: 'squat',
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: '${workoutId}_set1',
          workoutExerciseId: '${workoutId}_ex1',
          setIndex: 0,
          weightKg: 100,
          reps: 5,
          isCompleted: const Value(true),
        ),
      ],
    );
  }

  group('WorkoutDao', () {
    test('getWithDetails joins the exercise name', () async {
      await insertSampleWorkout('w1');

      final details = await workoutDao.getWithDetails('w1');

      expect(details, isNotNull);
      expect(details!.exercises, hasLength(1));
      expect(details.exerciseNames['w1_ex1'], 'Back Squat');
      expect(details.setsByExercise['w1_ex1'], hasLength(1));
      expect(details.setsByExercise['w1_ex1']!.single.weightKg, 100);
    });

    test('deleteWorkout cascades to exercises and sets', () async {
      await insertSampleWorkout('w1');

      await workoutDao.deleteWorkout('w1');

      expect(await workoutDao.getWithDetails('w1'), isNull);
      final orphanSets = await database.customSelect(
        'SELECT COUNT(*) AS c FROM workout_sets_table '
        'WHERE workout_exercise_id = ?',
        variables: [Variable.withString('w1_ex1')],
      ).getSingle();
      expect(orphanSets.data['c'], 0);
    });

    test('groups completed workouts into weekly frequency in SQL', () async {
      // Mon 5 Jan and Wed 7 Jan share a week; Mon 19 Jan is two weeks later,
      // so the week of 12 Jan sits empty between them.
      await insertSampleWorkout('w1', startedAt: DateTime.utc(2026, 1, 5));
      await insertSampleWorkout('w2', startedAt: DateTime.utc(2026, 1, 7));
      await insertSampleWorkout('w3', startedAt: DateTime.utc(2026, 1, 19));

      final frequency = await workoutDao.watchWorkoutFrequency().first;

      expect(frequency[0].weekStart, DateTime(2026, 1, 5));
      expect(frequency[0].workoutCount, 2);
      expect(frequency[1].weekStart, DateTime(2026, 1, 12));
      expect(frequency[1].workoutCount, 0);
      expect(frequency[2].weekStart, DateTime(2026, 1, 19));
      expect(frequency[2].workoutCount, 1);
    });

    group('weekly series gap-filling', () {
      // `GROUP BY` emits nothing for a week without workouts, which silently
      // deletes rest weeks from the x axis and makes any average over the
      // series measure active weeks rather than elapsed ones. Both weekly
      // queries zero-fill instead.

      test('emits a zero week between two trained weeks', () async {
        await insertSampleWorkout('w1', startedAt: DateTime.utc(2026, 1, 5));
        await insertSampleWorkout('w2', startedAt: DateTime.utc(2026, 1, 19));

        final volume = await workoutDao.watchWeeklyVolume().first;

        expect(volume[0].weekStart, DateTime(2026, 1, 5));
        expect(volume[0].totalVolumeKg, 500);
        expect(volume[1].weekStart, DateTime(2026, 1, 12));
        expect(volume[1].totalVolumeKg, 0);
        expect(volume[2].weekStart, DateTime(2026, 1, 19));
        expect(volume[2].totalVolumeKg, 500);
      });

      test('runs through the current week, so a layoff stays visible',
          () async {
        final DateTime start = DateTime.now().toUtc().subtract(
              const Duration(days: 28),
            );
        await insertSampleWorkout('w1', startedAt: start);

        final frequency = await workoutDao.watchWorkoutFrequency().first;

        // Four-ish weeks of nothing since, all present and all zero.
        expect(frequency.length, greaterThanOrEqualTo(4));
        expect(frequency.first.workoutCount, 1);
        expect(frequency.last.workoutCount, 0);
        expect(
          frequency.skip(1).every((f) => f.workoutCount == 0),
          isTrue,
        );
      });

      test(
          'a since bound starts the series at that week, not the first '
          'workout', () async {
        await insertSampleWorkout('w1', startedAt: DateTime.utc(2026, 1, 5));
        final DateTime since = DateTime.now().subtract(
          const Duration(days: 14),
        );

        final volume = await workoutDao.watchWeeklyVolume(since: since).first;

        // The 2026-01-05 workout is outside the window, so nothing matched
        // and nothing is fabricated.
        expect(volume, isEmpty);
      });

      test('consecutive buckets are exactly one week apart', () async {
        await insertSampleWorkout('w1', startedAt: DateTime.utc(2026, 1, 5));

        final volume = await workoutDao.watchWeeklyVolume().first;

        for (var i = 1; i < volume.length; i++) {
          expect(
            volume[i].weekStart.difference(volume[i - 1].weekStart).inDays,
            // Local-midnight dates a week apart are 7 days unless a DST
            // transition falls between them, which shortens or lengthens the
            // elapsed duration by an hour.
            inInclusiveRange(6, 8),
            reason: 'bucket $i is not one week after ${i - 1}',
          );
          expect(volume[i].weekStart.weekday, DateTime.monday);
        }
      });

      test('an empty result stays empty rather than a run of zeroes', () async {
        expect(await workoutDao.watchWeeklyVolume().first, isEmpty);
        expect(await workoutDao.watchWorkoutFrequency().first, isEmpty);
      });
    });

    test(
        'watchLoggedExercises returns only performed lifts, most-logged '
        'first', () async {
      await exerciseDao.upsertExercises([
        ExercisesTableCompanion.insert(
          id: 'bench',
          slug: 'bench',
          name: 'Bench Press',
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'horizontalPush',
          seedVersion: 1,
        ),
        // Never performed — the old picker listed the whole catalogue, so
        // exercises like this one were selectable and charted nothing.
        ExercisesTableCompanion.insert(
          id: 'deadlift',
          slug: 'deadlift',
          name: 'Deadlift',
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'hipDominant',
          seedVersion: 1,
        ),
      ]);
      await insertSampleWorkout('w1', startedAt: DateTime.utc(2026, 1, 5));
      await insertSampleWorkout('w2', startedAt: DateTime.utc(2026, 1, 12));
      await workoutDao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'w3',
          startedAt: DateTime.utc(2026, 1, 19),
          endedAt: Value(DateTime.utc(2026, 1, 19, 1)),
          totalVolumeKg: const Value(200),
        ),
        [
          WorkoutExercisesTableCompanion.insert(
            id: 'w3_ex1',
            workoutId: 'w3',
            exerciseId: 'bench',
            orderIndex: 0,
          ),
        ],
        [
          WorkoutSetsTableCompanion.insert(
            id: 'w3_set1',
            workoutExerciseId: 'w3_ex1',
            setIndex: 0,
            weightKg: 60,
            reps: 5,
            isCompleted: const Value(true),
          ),
        ],
      );

      final logged = await workoutDao.watchLoggedExercises().first;

      expect(logged.map((e) => e.exerciseId), ['squat', 'bench']);
      expect(logged.first.sessionCount, 2);
      expect(logged.last.sessionCount, 1);
    });

    test('updateWorkout replaces exercises/sets and recomputes volume',
        () async {
      await insertSampleWorkout('w1');

      await workoutDao.updateWorkout(
        workoutId: 'w1',
        totalVolumeKg: 240,
        exercises: [
          WorkoutExercisesTableCompanion.insert(
            id: 'w1_ex_new',
            workoutId: 'w1',
            exerciseId: 'squat',
            orderIndex: 0,
          ),
        ],
        sets: [
          WorkoutSetsTableCompanion.insert(
            id: 'w1_set_new',
            workoutExerciseId: 'w1_ex_new',
            setIndex: 0,
            weightKg: 80,
            reps: 3,
            isCompleted: const Value(true),
          ),
        ],
      );

      final details = await workoutDao.getWithDetails('w1');
      expect(details!.workout.totalVolumeKg, 240);
      expect(details.exercises.single.id, 'w1_ex_new');
      expect(details.setsByExercise['w1_ex_new']!.single.weightKg, 80);
      // The old exercise row (and its cascaded set) must be gone.
      expect(details.exerciseNames.containsKey('w1_ex1'), isFalse);
    });
  });
}
