import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';

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

    test(
        'compares against an earlier session even when both fall inside '
        'the window, once the window predates both', () async {
      final DateTime now = DateTime.now();
      // A brand-new lifter: every session for this exercise sits well
      // inside any preset range, so there is never an equal-length window
      // "before" the range to compare against — the old design read this
      // as "new" under every range, including the shortest one.
      await addWorkout(
          'first', now.subtract(const Duration(days: 8)), [('bench', 60, 5)]);
      await addWorkout('second', now.subtract(const Duration(days: 1)),
          [('bench', 70, 5)]);

      for (final Duration window in [
        const Duration(days: 30),
        const Duration(days: 90),
        const Duration(days: 365),
      ]) {
        final rows =
            await dao.watchStrengthChange(since: now.subtract(window)).first;
        expect(rows.single.isNew, isFalse, reason: '$window window');
        expect(rows.single.currentBestKg, closeTo(70 * (1 + 5 / 30), 0.001),
            reason: '$window window');
        expect(rows.single.previousBestKg, closeTo(60 * (1 + 5 / 30), 0.001),
            reason: '$window window');
      }
    });

    test('all-time compares against an earlier session when one exists',
        () async {
      await addWorkout('old', DateTime(2020, 1, 1), [('bench', 100, 5)]);
      await addWorkout('new', DateTime(2020, 2, 1), [('bench', 110, 5)]);

      final rows = await dao.watchStrengthChange().first;

      expect(rows.single.previousBestKg, closeTo(100 * (1 + 5 / 30), 0.001));
      expect(rows.single.change, closeTo(0.1, 0.001));
    });

    test(
        'the comparison point is the latest qualifying session, not the '
        'window\'s single heaviest set', () async {
      final DateTime now = DateTime.now();
      // A heavier one-off two weeks ago must not outrank last night's
      // session as "current" — current means most recent, not heaviest.
      await addWorkout(
          'heavier_earlier',
          now.subtract(const Duration(days: 14)),
          [('bench', 120, 5)]);
      await addWorkout('lighter_latest', now.subtract(const Duration(days: 1)),
          [('bench', 90, 5)]);

      final rows = await dao
          .watchStrengthChange(since: now.subtract(const Duration(days: 30)))
          .first;

      expect(rows.single.currentBestKg, closeTo(90 * (1 + 5 / 30), 0.001));
      expect(rows.single.previousBestKg, closeTo(120 * (1 + 5 / 30), 0.001));
      expect(rows.single.change, lessThan(0));
    });
  });

  group('watchOneRMSeries', () {
    test('collapses several sets in one session to a single best-1RM point',
        () async {
      // 60x10 -> 80.0, 100x1 -> 100.0, 90x5 -> 105.0. A drop-set-style
      // session like this must plot as one point (the 90x5 best), not
      // three points on the same date.
      await addWorkout('w1', DateTime(2026, 1, 10), [
        ('bench', 60, 10),
        ('bench', 100, 1),
        ('bench', 90, 5),
      ]);

      final points = await dao.watchOneRMSeries('bench').first;

      expect(points, hasLength(1));
      expect(points.single.estimated1RM, closeTo(90 * (1 + 5 / 30), 0.001));
    });

    test('returns one point per session, oldest first', () async {
      await addWorkout('w1', DateTime(2026, 1, 1), [('bench', 100, 5)]);
      await addWorkout('w2', DateTime(2026, 1, 8), [('bench', 105, 5)]);

      final points = await dao.watchOneRMSeries('bench').first;

      expect(points, hasLength(2));
      expect(points.map((p) => p.date),
          [DateTime(2026, 1, 8), DateTime(2026, 1, 1)]);
    });

    test('limit caps the number of sessions, not the number of sets', () async {
      await addWorkout('w1', DateTime(2026, 1, 1),
          [('bench', 100, 5), ('bench', 90, 8), ('bench', 80, 10)]);
      await addWorkout('w2', DateTime(2026, 1, 8), [('bench', 105, 5)]);

      final points = await dao.watchOneRMSeries('bench', limit: 1).first;

      // Without the fix, `limit` counted rows (sets), so the single most
      // recent *set* — not session — would be returned. With one row per
      // session, limiting to 1 must still return the most recent session.
      expect(points, hasLength(1));
      expect(points.single.date, DateTime(2026, 1, 8));
    });
  });

  group('watchPersonalRecordWorkoutIds', () {
    test('flags the first-ever workout for a lift as a PR', () async {
      await addWorkout('w1', DateTime(2026, 1, 1), [('bench', 100, 5)]);

      final ids = await dao.watchPersonalRecordWorkoutIds().first;

      expect(ids, {'w1'});
    });

    test('flags only workouts that beat every strictly earlier one', () async {
      await addWorkout('w1', DateTime(2026, 1, 1), [('bench', 100, 5)]);
      await addWorkout('w2', DateTime(2026, 1, 8), [('bench', 110, 5)]);
      // Lower than w2's best — not a PR.
      await addWorkout('w3', DateTime(2026, 1, 15), [('bench', 90, 5)]);
      await addWorkout('w4', DateTime(2026, 1, 22), [('bench', 120, 5)]);

      final ids = await dao.watchPersonalRecordWorkoutIds().first;

      expect(ids, {'w1', 'w2', 'w4'});
    });

    test('a workout counts if any one of its sets is a PR, not just its best',
        () async {
      await addWorkout('w1', DateTime(2026, 1, 1), [('bench', 100, 5)]);
      // 90x5 (~105) doesn't beat w1, but 60x1 (=110... no: 60 flat) doesn't
      // either. Use a set that clearly does: 105x5 (~122.5) beats w1's
      // ~116.7, alongside a non-PR set in the same workout.
      await addWorkout('w2', DateTime(2026, 1, 8), [
        ('bench', 80, 5), // not a PR on its own
        ('bench', 105, 5), // is a PR
      ]);

      final ids = await dao.watchPersonalRecordWorkoutIds().first;

      expect(ids, {'w1', 'w2'});
    });

    test('a PR on one exercise does not flag other exercises in the workout',
        () async {
      await addWorkout(
          'w1', DateTime(2026, 1, 1), [('bench', 100, 5), ('squat', 140, 5)]);
      // Only bench improves; squat regresses relative to w1.
      await addWorkout(
          'w2', DateTime(2026, 1, 8), [('bench', 110, 5), ('squat', 100, 5)]);

      final ids = await dao.watchPersonalRecordWorkoutIds().first;

      expect(ids, {'w1', 'w2'});
    });

    test('ignores warm-up and incomplete sets', () async {
      await addWorkout('w1', DateTime(2026, 1, 1), [('bench', 100, 5)]);
      // A huge warm-up-flagged set must not count as a PR on its own.
      await addWorkout(
        'w2',
        DateTime(2026, 1, 8),
        [('bench', 500, 5), ('bench', 90, 5)],
        warmupFirst: true,
      );

      final ids = await dao.watchPersonalRecordWorkoutIds().first;

      expect(ids, {'w1'});
    });
  });
}
