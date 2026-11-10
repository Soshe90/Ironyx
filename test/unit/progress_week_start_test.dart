import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/formatters/date_formatters.dart';
import 'package:ironyx/core/formatters/week_start.dart';
import 'package:ironyx/core/formatters/week_start_controller.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/features/progress/domain/consistency_calculators.dart';
import 'package:ironyx/features/progress/domain/progress_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Progress page's weekly series read the first day of the week from
/// Settings and bucket in the device's time.
///
/// The DAO and the calculators are covered on their own; this is the wiring
/// between them, where a forgotten argument would silently mean "Monday,
/// in UTC" while the dashboard and the calendar used the chosen day.
void main() {
  // todayProvider observes the app lifecycle through WidgetsBinding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;

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
        isBodyweight: const Value(false),
        seedVersion: 1,
      ),
    ]);
  });

  tearDown(() => database.close());

  Future<void> log(String id, DateTime startedAt) =>
      WorkoutDao(database).insertWorkout(
        WorkoutsTableCompanion.insert(
          id: id,
          startedAt: startedAt,
          endedAt: Value(startedAt.add(const Duration(minutes: 30))),
          totalVolumeKg: const Value(500),
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
            weightKg: 100,
            reps: 5,
            isCompleted: const Value(true),
          ),
        ],
      );

  Future<ProviderContainer> containerWith(WeekStart? weekStart) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      if (weekStart != null) 'week_start': weekStart.name,
    });
    final ProviderContainer container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  for (final WeekStart start in WeekStart.values) {
    group('week starting ${start.name}', () {
      test('the weekly series are bucketed from that day', () async {
        await log('a', DateTime(2026, 1, 9, 12));
        final container = await containerWith(start);
        const ProgressRange range = ProgressRange.all;

        final frequency = await (container
              ..listen(workoutFrequencySeriesProvider(range), (_, __) {}))
            .read(workoutFrequencySeriesProvider(range).future);
        final volume = await (container
              ..listen(weeklyVolumeSeriesProvider(range), (_, __) {}))
            .read(weeklyVolumeSeriesProvider(range).future);

        final DateTime week =
            DateFormatters.startOfWeek(DateTime(2026, 1, 9), start);
        expect(frequency.first.weekStart, week);
        expect(volume.first.weekStart, week);
        expect(
          frequency.every((f) => f.weekStart.weekday == start.weekday),
          isTrue,
        );
      });

      test('the weekday chart lists the days from that day', () async {
        await log('a', DateTime(2026, 1, 9, 12));
        final container = await containerWith(start);
        const ProgressRange range = ProgressRange.all;

        final days = await (container
              ..listen(weekdayDistributionProvider(range), (_, __) {}))
            .read(weekdayDistributionProvider(range).future);

        expect(days.map((d) => d.weekday), start.weekdays);
        expect(
          days.singleWhere((d) => d.workoutCount == 1).weekday,
          DateTime.friday,
        );
      });

      test('the current streak finds this week and last week', () async {
        // Now and seven days ago: this week and the one before, whichever
        // day the week starts on and whatever the time is.
        final DateTime now = DateTime.now();
        await log('this-week', now);
        await log('last-week', DateTime(now.year, now.month, now.day - 7, 12));
        final container = await containerWith(start);
        const ProgressRange range = ProgressRange.all;

        final ConsistencySummary summary = await (container
              ..listen(consistencySummaryProvider(range), (_, __) {}))
            .read(consistencySummaryProvider(range).future);

        expect(summary.currentStreakWeeks, 2);
        expect(summary.longestStreakWeeks, 2);
      });
    });
  }

  test('a workout in the first minutes of a week is in that week, device time',
      () async {
    // Sun 11 Jan 2026, 00:30 and Sat 17 Jan, 23:30, local: the two ends of
    // a week that starts on Sunday. In UTC one of them is in a neighbouring
    // week wherever this runs except in UTC itself.
    await log('first-minutes', DateTime(2026, 1, 11, 0, 30));
    await log('last-minutes', DateTime(2026, 1, 17, 23, 30));
    final container = await containerWith(WeekStart.sunday);
    const ProgressRange range = ProgressRange.all;

    final frequency = await (container
          ..listen(workoutFrequencySeriesProvider(range), (_, __) {}))
        .read(workoutFrequencySeriesProvider(range).future);
    final days = await (container
          ..listen(weekdayDistributionProvider(range), (_, __) {}))
        .read(weekdayDistributionProvider(range).future);

    expect(frequency.first.weekStart, DateTime(2026, 1, 11));
    expect(frequency.first.workoutCount, 2);
    expect(days.first.weekday, DateTime.sunday);
    expect(days.first.workoutCount, 1);
    expect(days.last.weekday, DateTime.saturday);
    expect(days.last.workoutCount, 1);
  });

  test('changing the day regroups a series that is already showing', () async {
    await log('a', DateTime(2026, 1, 9, 12));
    final container = await containerWith(null);
    const ProgressRange range = ProgressRange.all;

    final before = await (container
          ..listen(workoutFrequencySeriesProvider(range), (_, __) {}))
        .read(workoutFrequencySeriesProvider(range).future);
    expect(before.first.weekStart, DateTime(2026, 1, 5));

    await container
        .read(weekStartControllerProvider.notifier)
        .set(WeekStart.saturday);
    final after =
        await container.read(workoutFrequencySeriesProvider(range).future);

    expect(after.first.weekStart, DateTime(2026, 1, 3));
    expect(after.first.workoutCount, 1);
  });
}
