import 'package:drift/drift.dart' hide isNull;
import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/workout_dao.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the two raw-SQL strength queries against a real database.
///
/// `customSelect` compiles and passes `flutter analyze` regardless of
/// whether the SQL is right, so these only mean anything when run against
/// seeded rows — the same trap that hid two broken DAO queries until M5.
void main() {
  late AppDatabase db;
  late WorkoutDao dao;

  setUp(() async {
    db = AppDatabase.forTesting();
    dao = WorkoutDao(db);
    await ExerciseDao(db).upsertExercises([
      for (final (String id, String name) in <(String, String)>[
        ('bench', 'Bench Press'),
        ('squat', 'Back Squat'),
      ])
        ExercisesTableCompanion.insert(
          id: id,
          slug: id,
          name: name,
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'horizontalPush',
          seedVersion: 1,
        ),
    ]);
  });

  tearDown(() => db.close());

  /// Inserts one workout with a set per (exerciseId, weight, reps) entry.
  Future<void> addWorkout(
    String id,
    DateTime startedAt,
    List<(String, double, int)> sets, {
    bool warmupFirst = false,
  }) async {
    final exerciseIds = <String>{for (final s in sets) s.$1}.toList();
    await dao.insertWorkout(
      WorkoutsTableCompanion.insert(
        id: id,
        startedAt: startedAt,
        endedAt: Value(startedAt.add(const Duration(hours: 1))),
      ),
      [
        for (var i = 0; i < exerciseIds.length; i++)
          WorkoutExercisesTableCompanion.insert(
            id: '${id}_${exerciseIds[i]}',
            workoutId: id,
            exerciseId: exerciseIds[i],
            orderIndex: i,
          ),
      ],
      [
        for (var i = 0; i < sets.length; i++)
          WorkoutSetsTableCompanion.insert(
            id: '${id}_set_$i',
            workoutExerciseId: '${id}_${sets[i].$1}',
            setIndex: i,
            weightKg: sets[i].$2,
            reps: sets[i].$3,
            isCompleted: const Value(true),
            isWarmup: Value(warmupFirst && i == 0),
          ),
      ],
    );
  }

  group('watchWorkoutPerformance', () {
    test('reports the best set, not the last or the heaviest-by-weight',
        () async {
      // 60x10 -> 80.0, 100x1 -> 100.0, 90x5 -> 105.0. The best 1RM is the
      // 90x5, which is neither the last set nor the heaviest weight.
      await addWorkout('w1', DateTime(2026, 1, 10), [
        ('bench', 60, 10),
        ('bench', 100, 1),
        ('bench', 90, 5),
      ]);

      final rows = await dao.watchWorkoutPerformance('w1').first;

      expect(rows, hasLength(1));
      expect(rows.single.bestWeightKg, 90);
      expect(rows.single.bestReps, 5);
      expect(rows.single.bestOneRmKg, closeTo(105, 0.001));
    });

    test('compares against the best before this workout only', () async {
      await addWorkout('w1', DateTime(2026, 1, 1), [('bench', 100, 5)]);
      await addWorkout('w2', DateTime(2026, 1, 8), [('bench', 110, 5)]);
      // A later, heavier session must not leak into w2's "previous".
      await addWorkout('w3', DateTime(2026, 1, 15), [('bench', 200, 5)]);

      final rows = await dao.watchWorkoutPerformance('w2').first;

      expect(rows.single.previousBestKg, closeTo(100 * (1 + 5 / 30), 0.001));
      expect(rows.single.isPersonalRecord, isTrue);
      expect(rows.single.change, closeTo(0.1, 0.001));
    });

    test('a first-ever attempt is not a regression', () async {
      await addWorkout('w1', DateTime(2026, 1, 1), [('bench', 100, 5)]);

      final rows = await dao.watchWorkoutPerformance('w1').first;

      expect(rows.single.previousBestKg, isNull);
      expect(rows.single.isFirstTime, isTrue);
      expect(rows.single.isPersonalRecord, isFalse);
      expect(rows.single.change, isNull);
    });

    test('ignores warm-up sets', () async {
      await addWorkout(
        'w1',
        DateTime(2026, 1, 1),
        [('bench', 500, 5), ('bench', 100, 5)],
        warmupFirst: true,
      );

      final rows = await dao.watchWorkoutPerformance('w1').first;

      expect(rows.single.bestWeightKg, 100);
    });

    test('returns one row per exercise, in workout order', () async {
      await addWorkout('w1', DateTime(2026, 1, 1), [
        ('bench', 100, 5),
        ('squat', 140, 5),
      ]);

      final rows = await dao.watchWorkoutPerformance('w1').first;

      expect(rows.map((r) => r.exerciseName), ['Bench Press', 'Back Squat']);
    });
  });

  group('watchStrengthChange', () {
    test('compares a window against the one immediately before it', () async {
      final DateTime now = DateTime.now();
      // 40 days ago falls in the previous 30-day window; 10 days ago in
      // the current one.
      await addWorkout(
          'old', now.subtract(const Duration(days: 40)), [('bench', 100, 5)]);
      await addWorkout('recent', now.subtract(const Duration(days: 10)),
          [('bench', 110, 5)]);

      final rows = await dao
          .watchStrengthChange(since: now.subtract(const Duration(days: 30)))
          .first;

      expect(rows, hasLength(1));
      expect(rows.single.currentBestKg, closeTo(110 * (1 + 5 / 30), 0.001));
      expect(rows.single.previousBestKg, closeTo(100 * (1 + 5 / 30), 0.001));
      expect(rows.single.change, closeTo(0.1, 0.001));
    });

    test('a lift only trained this window has no comparison', () async {
      final DateTime now = DateTime.now();
      await addWorkout(
          'recent', now.subtract(const Duration(days: 5)), [('squat', 140, 5)]);

      final rows = await dao
          .watchStrengthChange(since: now.subtract(const Duration(days: 30)))
          .first;

      expect(rows.single.isNew, isTrue);
      expect(rows.single.change, isNull);
    });

    test('all-time reports a best with nothing to compare against', () async {
      await addWorkout('w1', DateTime(2020, 1, 1), [('bench', 100, 5)]);

      final rows = await dao.watchStrengthChange().first;

      expect(rows.single.currentBestKg, closeTo(100 * (1 + 5 / 30), 0.001));
      expect(rows.single.previousBestKg, isNull);
    });

    test('orders the heaviest lift first', () async {
      final DateTime now = DateTime.now();
      await addWorkout('w1', now.subtract(const Duration(days: 2)), [
        ('bench', 100, 5),
        ('squat', 140, 5),
      ]);

      final rows = await dao
          .watchStrengthChange(since: now.subtract(const Duration(days: 30)))
          .first;

      expect(rows.map((r) => r.exerciseName), ['Back Squat', 'Bench Press']);
    });
  });
}
