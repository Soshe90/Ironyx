import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/services/clock.dart';
import 'package:ironyx/features/dashboard/domain/dashboard_providers.dart';
import 'package:ironyx/features/dashboard/domain/strength_headline.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home's "Est. 1RM" tile: which lift, which figure, which arrow.
void main() {
  // LocalNow observes the app lifecycle through WidgetsBinding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('pickStrengthHeadline', () {
    LoggedExercise lift(String id, int sessions) => LoggedExercise(
        exerciseId: id, exerciseName: id, sessionCount: sessions);
    StrengthChange row(
      String id,
      double best, {
      double? previous,
      bool firstSession = false,
    }) =>
        StrengthChange(
          exerciseId: id,
          exerciseName: id,
          currentBestKg: best,
          previousBestKg: previous,
          comparedWithFirstSession: firstSession,
        );

    OneRMTrend? trendFor(double best, {double? previous, bool first = false}) =>
        pickStrengthHeadline(
          lifts: <LoggedExercise>[lift('bench', 5)],
          recent: <StrengthChange>[
            row('bench', best, previous: previous, firstSession: first),
          ],
          allTime: const <StrengthChange>[],
        )!
            .trend;

    test('nothing logged shows nothing', () {
      expect(
        pickStrengthHeadline(
          lifts: const <LoggedExercise>[],
          recent: const <StrengthChange>[],
          allTime: const <StrengthChange>[],
        ),
        isNull,
      );
    });

    test('the most-trained lift trained lately, at its best', () {
      final StrengthHeadline h = pickStrengthHeadline(
        // Squat is trained most but not in the last three months.
        lifts: <LoggedExercise>[lift('squat', 40), lift('bench', 12)],
        recent: <StrengthChange>[
          row('row', 120, previous: 100),
          row('bench', 100, previous: 90),
        ],
        allTime: <StrengthChange>[row('squat', 180)],
      )!;
      expect(h.exerciseId, 'bench');
      expect(h.bestKg, 100);
      expect(h.trend, OneRMTrend.up);
    });

    test('under 2.5% either way is flat', () {
      expect(trendFor(102.4, previous: 100), OneRMTrend.flat);
      expect(trendFor(97.6, previous: 100), OneRMTrend.flat);
      expect(trendFor(100, previous: 100), OneRMTrend.flat);
    });

    test('2.5% and more is a direction', () {
      expect(trendFor(103, previous: 100), OneRMTrend.up);
      expect(trendFor(97, previous: 100), OneRMTrend.down);
    });

    test('no arrow without an earlier best, or against a first session', () {
      expect(trendFor(100), isNull);
      expect(trendFor(140, previous: 60, first: true), isNull,
          reason: 'people start light; +133% is not a strength change');
    });

    test('after a break: the main lift at its all-time best, no arrow', () {
      final StrengthHeadline h = pickStrengthHeadline(
        lifts: <LoggedExercise>[lift('squat', 40), lift('bench', 12)],
        recent: const <StrengthChange>[],
        allTime: <StrengthChange>[
          row('bench', 100, previous: 60, firstSession: true),
          row('squat', 180, previous: 60, firstSession: true),
        ],
      )!;
      expect(h.exerciseId, 'squat');
      expect(h.bestKg, 180);
      expect(h.trend, isNull);
    });
  });

  group('dashboardStrengthHeadline', () {
    late AppDatabase database;
    // Tue 10 Nov 2026, noon. "3M" starts 90 days earlier, on 12 Aug.
    final DateTime now = DateTime(2026, 11, 10, 12);

    setUp(() async {
      database = AppDatabase.forTesting();
      await ExerciseDao(database).upsertExercises([
        ExercisesTableCompanion.insert(
          id: 'squat',
          slug: 'squat',
          name: 'Back Squat',
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'kneeDominant',
          seedVersion: 1,
        ),
      ]);
    });

    tearDown(() => database.close());

    Future<void> squat(String id, DateTime at, double kg) =>
        WorkoutDao(database).insertWorkout(
          WorkoutsTableCompanion.insert(
            id: id,
            startedAt: at,
            endedAt: Value(at.add(const Duration(minutes: 45))),
          ),
          [
            WorkoutExercisesTableCompanion.insert(
              id: '${id}_ex',
              workoutId: id,
              exerciseId: 'squat',
              orderIndex: 0,
            ),
          ],
          [
            WorkoutSetsTableCompanion.insert(
              id: '${id}_set',
              workoutExerciseId: '${id}_ex',
              setIndex: 0,
              weightKg: kg,
              reps: 1,
              isCompleted: const Value(true),
            ),
          ],
        );

    Future<StrengthHeadline?> headline() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider
              .overrideWithValue(await SharedPreferences.getInstance()),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      container.listen(dashboardStrengthHeadlineProvider, (_, __) {});
      return container.read(dashboardStrengthHeadlineProvider.future);
    }

    test('a light day does not lower the figure or turn the arrow red',
        () async {
      await squat('june', DateTime(2026, 6, 1, 18), 140);
      await squat('heavy', DateTime(2026, 10, 1, 18), 150);
      await squat('deload', DateTime(2026, 11, 9, 18), 110);

      final StrengthHeadline h = (await headline())!;
      // The old tile: 110 kg, down, against the session before it.
      expect(h.bestKg, 150);
      expect(h.trend, OneRMTrend.up, reason: '150 against 140 before 3M');
    });

    test('a best within 2.5% of the one before the window is flat', () async {
      await squat('june', DateTime(2026, 6, 1, 18), 150);
      await squat('oct', DateTime(2026, 10, 1, 18), 148);

      final StrengthHeadline h = (await headline())!;
      expect(h.bestKg, 148);
      expect(h.trend, OneRMTrend.flat,
          reason: '-1.3%: the old tile had no threshold');
    });

    test('nothing for three months: the all-time best, no arrow', () async {
      await squat('march', DateTime(2026, 3, 1, 18), 120);
      await squat('may', DateTime(2026, 5, 1, 18), 130);

      final StrengthHeadline h = (await headline())!;
      expect(h.bestKg, 130);
      expect(h.trend, isNull);
    });
  });
}
