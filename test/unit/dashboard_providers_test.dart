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
import 'package:ironyx/core/services/clock.dart';
import 'package:ironyx/features/dashboard/domain/dashboard_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the two new dashboard-card queries added in M6:
/// `ExerciseDao.watchLibrarySummary` and
/// `WorkoutDao.watchMostLoggedExerciseOneRM`. The dashboard's Riverpod
/// providers are thin pass-throughs over these — this is where the actual
/// logic (and the empty-state case) lives.
void main() {
  // LocalNow observes the app lifecycle through WidgetsBinding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ExerciseDao exerciseDao;
  late WorkoutDao workoutDao;

  setUp(() {
    database = AppDatabase.forTesting();
    exerciseDao = ExerciseDao(database);
    workoutDao = WorkoutDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedExercise(String id, String name) =>
      exerciseDao.upsertExercises([
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

  Future<void> insertWorkoutWithSet({
    required String workoutId,
    required String exerciseId,
    required DateTime startedAt,
    required double weightKg,
    required int reps,
  }) {
    return workoutDao.insertWorkout(
      WorkoutsTableCompanion.insert(
        id: workoutId,
        startedAt: startedAt,
        endedAt: Value(startedAt.add(const Duration(minutes: 30))),
        totalVolumeKg: Value(weightKg * reps),
      ),
      [
        WorkoutExercisesTableCompanion.insert(
          id: '${workoutId}_ex',
          workoutId: workoutId,
          exerciseId: exerciseId,
          orderIndex: 0,
        ),
      ],
      [
        WorkoutSetsTableCompanion.insert(
          id: '${workoutId}_set',
          workoutExerciseId: '${workoutId}_ex',
          setIndex: 0,
          weightKg: weightKg,
          reps: reps,
          isCompleted: const Value(true),
        ),
      ],
    );
  }

  group('WeekSnapshot.from', () {
    test('empty series produces a zeroed no-history snapshot', () {
      final snapshot = WeekSnapshot.from(
        weekStart: WeekStart.monday,
        volume: const <WeeklyVolume>[],
        frequency: const <WorkoutFrequency>[],
      );

      expect(snapshot.volumeKg, 0);
      expect(snapshot.previousVolumeKg, 0);
      expect(snapshot.sessions, 0);
      expect(snapshot.volumeSeries, isEmpty);
      expect(snapshot.hasHistory, isFalse);
    });

    test('selects current and previous weeks and preserves series length', () {
      final DateTime currentWeek =
          DateFormatters.startOfWeek(DateTime.now(), WeekStart.monday);
      final DateTime previousWeek =
          currentWeek.subtract(const Duration(days: 7));
      final DateTime olderWeek = previousWeek.subtract(const Duration(days: 7));

      final snapshot = WeekSnapshot.from(
        weekStart: WeekStart.monday,
        volume: <WeeklyVolume>[
          WeeklyVolume(weekStart: olderWeek, totalVolumeKg: 50),
          WeeklyVolume(weekStart: previousWeek, totalVolumeKg: 100),
          WeeklyVolume(weekStart: currentWeek, totalVolumeKg: 150),
        ],
        frequency: <WorkoutFrequency>[
          WorkoutFrequency(weekStart: olderWeek, workoutCount: 1),
          WorkoutFrequency(weekStart: previousWeek, workoutCount: 2),
          WorkoutFrequency(weekStart: currentWeek, workoutCount: 3),
        ],
      );

      expect(snapshot.volumeKg, 150);
      expect(snapshot.previousVolumeKg, 100);
      expect(snapshot.sessions, 3);
      expect(snapshot.volumeSeries, <double>[50, 100, 150]);
      expect(snapshot.hasHistory, isTrue);
    });

    // The streak is no longer part of the snapshot (it saw only eight
    // weeks). Its cases are in consistency_calculators_test.dart under
    // currentStreakWeeks, and the provider's are in "the streak tile".
  });

  group('ExerciseDao.watchLibrarySummary', () {
    test('empty catalogue reports zero count and no recent name', () async {
      final summary = await exerciseDao.watchLibrarySummary().first;
      expect(summary.count, 0);
      expect(summary.mostRecentName, isNull);
    });

    test('counts exercises and names the most recently added', () async {
      await seedExercise('bench', 'Bench Press');
      await seedExercise('squat', 'Back Squat');

      final summary = await exerciseDao.watchLibrarySummary().first;
      expect(summary.count, 2);
      // Both rows share the same default createdAt in this test (inserted
      // back-to-back), so just assert it resolves to one of the two names
      // rather than asserting a specific insertion-order tie-break.
      expect(summary.mostRecentName, anyOf('Bench Press', 'Back Squat'));
    });
  });

  group('WorkoutDao.watchAverageDurationSeconds', () {
    test('ignores incomplete and legacy workouts without durations', () async {
      await workoutDao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'incomplete',
          startedAt: DateTime.utc(2026, 1, 1),
          durationSeconds: const Value(60),
        ),
        const [],
        const [],
      );
      await workoutDao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'legacy',
          startedAt: DateTime.utc(2026, 1, 2),
          endedAt: Value(DateTime.utc(2026, 1, 2, 0, 30)),
        ),
        const [],
        const [],
      );

      expect(await workoutDao.watchAverageDurationSeconds().first, isNull);
    });

    test('averages recorded completed workout durations', () async {
      await workoutDao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'short',
          startedAt: DateTime.utc(2026, 1, 1),
          endedAt: Value(DateTime.utc(2026, 1, 1, 0, 20)),
          durationSeconds: const Value(1200),
        ),
        const [],
        const [],
      );
      await workoutDao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'long',
          startedAt: DateTime.utc(2026, 1, 2),
          endedAt: Value(DateTime.utc(2026, 1, 2, 1)),
          durationSeconds: const Value(3600),
        ),
        const [],
        const [],
      );

      expect(
        await workoutDao.watchAverageDurationSeconds().first,
        closeTo(2400, 0.001),
      );
    });
  });

  group('WorkoutDao.watchMostLoggedExerciseOneRM', () {
    test('no workouts yields null', () async {
      final result = await workoutDao.watchMostLoggedExerciseOneRM().first;
      expect(result, isNull);
    });

    test('picks the exercise with the most sets and reports an up trend',
        () async {
      await seedExercise('bench', 'Bench Press');
      await seedExercise('row', 'Barbell Row');

      // Bench: 3 sets across 3 workouts (most-logged). Row: 1 set.
      await insertWorkoutWithSet(
        workoutId: 'w1',
        exerciseId: 'bench',
        startedAt: DateTime.utc(2026, 1, 1),
        weightKg: 60,
        reps: 5,
      );
      await insertWorkoutWithSet(
        workoutId: 'w2',
        exerciseId: 'bench',
        startedAt: DateTime.utc(2026, 1, 8),
        weightKg: 65,
        reps: 5,
      );
      await insertWorkoutWithSet(
        workoutId: 'w3',
        exerciseId: 'bench',
        startedAt: DateTime.utc(2026, 1, 15),
        weightKg: 70,
        reps: 5,
      );
      await insertWorkoutWithSet(
        workoutId: 'w4',
        exerciseId: 'row',
        startedAt: DateTime.utc(2026, 1, 16),
        weightKg: 40,
        reps: 8,
      );

      final result = await workoutDao.watchMostLoggedExerciseOneRM().first;
      expect(result, isNotNull);
      expect(result!.exerciseName, 'Bench Press');
      // Epley: 70 * (1 + 5/30) ≈ 81.67, previous workout 65 * (1+5/30) ≈ 75.8
      expect(result.currentKg, closeTo(81.67, 0.1));
      expect(result.trend, OneRMTrend.up);
    });

    test('a single workout reports a flat trend (nothing to compare against)',
        () async {
      await seedExercise('bench', 'Bench Press');
      await insertWorkoutWithSet(
        workoutId: 'w1',
        exerciseId: 'bench',
        startedAt: DateTime.utc(2026, 1, 1),
        weightKg: 60,
        reps: 5,
      );

      final result = await workoutDao.watchMostLoggedExerciseOneRM().first;
      expect(result!.trend, OneRMTrend.flat);
    });
  });

  group('WeekSnapshot.from with an explicit today', () {
    test('"this week" follows the given day, not the device clock', () {
      final DateTime weekOfOct26 = DateTime(2026, 10, 26);
      final DateTime weekOfNov2 = DateTime(2026, 11, 2);
      final List<WeeklyVolume> volume = <WeeklyVolume>[
        WeeklyVolume(weekStart: weekOfOct26, totalVolumeKg: 100),
        WeeklyVolume(weekStart: weekOfNov2, totalVolumeKg: 250),
      ];
      final List<WorkoutFrequency> frequency = <WorkoutFrequency>[
        WorkoutFrequency(weekStart: weekOfOct26, workoutCount: 1),
        WorkoutFrequency(weekStart: weekOfNov2, workoutCount: 2),
      ];

      final WeekSnapshot friday = WeekSnapshot.from(
        weekStart: WeekStart.monday,
        volume: volume,
        frequency: frequency,
        today: DateTime(2026, 10, 30),
      );
      final WeekSnapshot tuesday = WeekSnapshot.from(
        weekStart: WeekStart.monday,
        volume: volume,
        frequency: frequency,
        today: DateTime(2026, 11, 3),
      );

      expect(friday.volumeKg, 100);
      expect(friday.sessions, 1);
      expect(tuesday.volumeKg, 250);
      expect(tuesday.previousVolumeKg, 100);
      expect(tuesday.sessions, 2);
    });
  });

  group('dashboardWeekSnapshot across a day change', () {
    // The dashboard tab stays alive in the shell. Before LocalNow, its week
    // window was captured once at first build, so an app left in memory
    // from Friday to Tuesday kept reporting the previous week.
    test('a workout from the new week appears once the day rolls over',
        () async {
      await seedExercise('bench', 'Bench Press');
      await insertWorkoutWithSet(
        workoutId: 'monday',
        exerciseId: 'bench',
        startedAt: DateTime(2026, 11, 2, 12),
        weightKg: 100,
        reps: 5,
      );

      DateTime fakeNow = DateTime(2026, 10, 30, 19, 50);
      // The week windows read the first day of the week from preferences.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider
              .overrideWithValue(await SharedPreferences.getInstance()),
          clockProvider.overrideWithValue(() => fakeNow),
        ],
      );
      addTearDown(container.dispose);
      // Keep the auto-dispose chain alive between reads, as the mounted
      // dashboard does.
      container.listen(dashboardWeekSnapshotProvider, (_, __) {});

      final WeekSnapshot before =
          await container.read(dashboardWeekSnapshotProvider.future);
      expect(before.sessions, 0, reason: 'Monday 2 Nov is next week on Fri');

      fakeNow = DateTime(2026, 11, 3, 11, 37);
      container.read(localNowProvider.notifier).refresh();

      final WeekSnapshot after =
          await container.read(dashboardWeekSnapshotProvider.future);
      expect(after.sessions, 1);
      expect(after.volumeKg, 500);
    });
  });

  group('the week card and the first day of the week', () {
    Future<ProviderContainer> containerAt(
      DateTime Function() now, {
      Map<String, Object> prefs = const <String, Object>{},
    }) async {
      SharedPreferences.setMockInitialValues(prefs);
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider
              .overrideWithValue(await SharedPreferences.getInstance()),
          clockProvider.overrideWithValue(now),
        ],
      );
      addTearDown(container.dispose);
      // Keep the auto-dispose chains alive between reads, as the mounted
      // dashboard does.
      container.listen(dashboardWeekSnapshotProvider, (_, __) {});
      container.listen(dashboardWeekdayDistributionProvider, (_, __) {});
      container.listen(dashboardStreakWeeksProvider, (_, __) {});
      return container;
    }

    /// Fri 30 Oct and Sat 31 Oct 2026 at local noon; "now" is Sun 1 Nov.
    Future<void> logFridayAndSaturday() async {
      await seedExercise('bench', 'Bench Press');
      await insertWorkoutWithSet(
        workoutId: 'friday',
        exerciseId: 'bench',
        startedAt: DateTime(2026, 10, 30, 12),
        weightKg: 100,
        reps: 1,
      );
      await insertWorkoutWithSet(
        workoutId: 'saturday',
        exerciseId: 'bench',
        startedAt: DateTime(2026, 10, 31, 12),
        weightKg: 100,
        reps: 2,
      );
    }

    test('sessions, last week and the streak regroup when the day changes',
        () async {
      await logFridayAndSaturday();
      final container = await containerAt(() => DateTime(2026, 11, 1, 12));
      final setting = container.read(weekStartControllerProvider.notifier);

      // Monday (nothing chosen): Mon 26 Oct to Sun 1 Nov holds both.
      WeekSnapshot week =
          await container.read(dashboardWeekSnapshotProvider.future);
      expect(week.sessions, 2);
      expect(week.volumeKg, 300);
      expect(week.previousVolumeKg, 0);
      expect(await container.read(dashboardStreakWeeksProvider.future), 1);

      // Saturday: this week began yesterday; Friday is last week.
      await setting.set(WeekStart.saturday);
      week = await container.read(dashboardWeekSnapshotProvider.future);
      expect(week.sessions, 1);
      expect(week.volumeKg, 200);
      expect(week.previousVolumeKg, 100);
      expect(await container.read(dashboardStreakWeeksProvider.future), 2);

      // Sunday: this week began today, with nothing in it yet; both are
      // last week, and the streak counts from there.
      await setting.set(WeekStart.sunday);
      week = await container.read(dashboardWeekSnapshotProvider.future);
      expect(week.sessions, 0);
      expect(week.volumeKg, 0);
      expect(week.previousVolumeKg, 300);
      expect(await container.read(dashboardStreakWeeksProvider.future), 1);

      // And back: nothing was stored by week, so nothing is lost.
      await setting.set(WeekStart.monday);
      week = await container.read(dashboardWeekSnapshotProvider.future);
      expect(week.sessions, 2);
      expect(week.volumeKg, 300);
    });

    test('a saved choice is used from the first read', () async {
      await logFridayAndSaturday();
      final container = await containerAt(
        () => DateTime(2026, 11, 1, 12),
        prefs: <String, Object>{'week_start': 'saturday'},
      );

      final WeekSnapshot week =
          await container.read(dashboardWeekSnapshotProvider.future);
      expect(week.sessions, 1);
    });

    test('the day strip starts on the chosen day and covers only this week',
        () async {
      await logFridayAndSaturday();
      final container = await containerAt(
        () => DateTime(2026, 11, 1, 12),
        prefs: <String, Object>{'week_start': 'saturday'},
      );

      final List<WeekdayDistribution> days =
          await container.read(dashboardWeekdayDistributionProvider.future);

      expect(days.map((d) => d.weekday), WeekStart.saturday.weekdays);
      expect(days.first.weekday, DateTime.saturday);
      expect(days.first.trainingDayCount, 1);
      // Friday is the strip's last cell, and this week's Friday has not
      // happened yet: last Friday's workout is not shown on it.
      expect(days.last.weekday, DateTime.friday);
      expect(days.last.trainingDayCount, 0);
    });

    test('the strip and the week card agree on which days are this week',
        () async {
      await logFridayAndSaturday();
      for (final WeekStart start in WeekStart.values) {
        final container = await containerAt(
          () => DateTime(2026, 11, 1, 12),
          prefs: <String, Object>{'week_start': start.name},
        );

        final WeekSnapshot week =
            await container.read(dashboardWeekSnapshotProvider.future);
        final List<WeekdayDistribution> days =
            await container.read(dashboardWeekdayDistributionProvider.future);

        expect(
          days.fold<int>(0, (sum, d) => sum + d.workoutCount),
          week.sessions,
          reason: '$start',
        );
        container.dispose();
      }
    });

    test('a workout just inside either end of the week, in device time',
        () async {
      // Mon 2 Nov 00:30 and Sun 8 Nov 23:30, local. In UTC one of them is
      // in a neighbouring week wherever this runs except in UTC itself:
      // the first east of it, the second west of it.
      await seedExercise('bench', 'Bench Press');
      await insertWorkoutWithSet(
        workoutId: 'first-minutes',
        exerciseId: 'bench',
        startedAt: DateTime(2026, 11, 2, 0, 30),
        weightKg: 100,
        reps: 1,
      );
      await insertWorkoutWithSet(
        workoutId: 'last-minutes',
        exerciseId: 'bench',
        startedAt: DateTime(2026, 11, 8, 23, 30),
        weightKg: 100,
        reps: 2,
      );
      final container = await containerAt(() => DateTime(2026, 11, 8, 23, 45));

      final WeekSnapshot week =
          await container.read(dashboardWeekSnapshotProvider.future);
      final List<WeekdayDistribution> days =
          await container.read(dashboardWeekdayDistributionProvider.future);

      expect(week.sessions, 2);
      expect(week.volumeKg, 300);
      expect(week.previousVolumeKg, 0);
      expect(days.first.weekday, DateTime.monday);
      expect(days.first.workoutCount, 1);
      expect(days.last.weekday, DateTime.sunday);
      expect(days.last.workoutCount, 1);
    });
  });

  group('WeekSnapshot.from', () {
    test('finds this week only with the first day the series uses', () {
      // Buckets for a week starting on Saturday: Sat 24 and Sat 31 Oct.
      final List<WeeklyVolume> volume = <WeeklyVolume>[
        WeeklyVolume(weekStart: DateTime(2026, 10, 24), totalVolumeKg: 100),
        WeeklyVolume(weekStart: DateTime(2026, 10, 31), totalVolumeKg: 250),
      ];
      final List<WorkoutFrequency> frequency = <WorkoutFrequency>[
        WorkoutFrequency(weekStart: DateTime(2026, 10, 24), workoutCount: 1),
        WorkoutFrequency(weekStart: DateTime(2026, 10, 31), workoutCount: 2),
      ];

      final WeekSnapshot saturday = WeekSnapshot.from(
        volume: volume,
        frequency: frequency,
        weekStart: WeekStart.saturday,
        today: DateTime(2026, 11, 3),
      );
      expect(saturday.sessions, 2);
      expect(saturday.volumeKg, 250);
      expect(saturday.previousVolumeKg, 100);

      // Asked with Monday, "this week" is Mon 2 Nov: no bucket is that day.
      final WeekSnapshot monday = WeekSnapshot.from(
        volume: volume,
        frequency: frequency,
        weekStart: WeekStart.monday,
        today: DateTime(2026, 11, 3),
      );
      expect(monday.sessions, 0);
    });

    test('last week survives a week in which the clocks change', () {
      // See the matching test in consistency_calculators_test.dart. Only a
      // zone that changes its clocks can tell: run with TZ=PST8PDT.
      for (final List<DateTime> mondays in <List<DateTime>>[
        <DateTime>[DateTime(2026, 3, 2), DateTime(2026, 3, 9)],
        <DateTime>[DateTime(2026, 3, 23), DateTime(2026, 3, 30)],
        <DateTime>[DateTime(2026, 10, 19), DateTime(2026, 10, 26)],
        <DateTime>[DateTime(2026, 10, 26), DateTime(2026, 11, 2)],
      ]) {
        final WeekSnapshot snapshot = WeekSnapshot.from(
          volume: <WeeklyVolume>[
            WeeklyVolume(weekStart: mondays[0], totalVolumeKg: 100),
            WeeklyVolume(weekStart: mondays[1], totalVolumeKg: 250),
          ],
          frequency: <WorkoutFrequency>[
            WorkoutFrequency(weekStart: mondays[0], workoutCount: 1),
            WorkoutFrequency(weekStart: mondays[1], workoutCount: 2),
          ],
          weekStart: WeekStart.monday,
          today:
              DateTime(mondays[1].year, mondays[1].month, mondays[1].day + 2),
        );

        expect(snapshot.volumeKg, 250, reason: 'weeks $mondays');
        expect(snapshot.previousVolumeKg, 100, reason: 'weeks $mondays');
      }
    });
  });

  group('last week up to the same point', () {
    test('watchVolumeBetween counts [from, until) and finished workouts only',
        () async {
      await seedExercise('bench', 'Bench Press');
      final WorkoutDao dao = WorkoutDao(database);
      Future<void> workout(String id, DateTime at, double kg,
              {bool ended = true}) =>
          dao.insertWorkout(
            WorkoutsTableCompanion.insert(
              id: id,
              startedAt: at,
              endedAt: ended
                  ? Value(at.add(const Duration(minutes: 30)))
                  : const Value.absent(),
              totalVolumeKg: Value(kg),
            ),
            const [],
            const [],
          );
      final DateTime from = DateTime(2026, 11, 2);
      final DateTime until = DateTime(2026, 11, 4, 12);
      await workout('before', from.subtract(const Duration(minutes: 1)), 1);
      await workout('atFrom', from, 10);
      await workout('inside', DateTime(2026, 11, 3, 18), 100);
      await workout('open', DateTime(2026, 11, 3, 19), 1000, ended: false);
      await workout('atUntil', until, 10000);

      expect(await dao.watchVolumeBetween(from, until).first, 110);
      expect(
        await dao
            .watchVolumeBetween(DateTime(2020, 1, 1), DateTime(2020, 1, 2))
            .first,
        0,
      );
    });

    test('this week so far is compared with last week to the same moment',
        () async {
      await seedExercise('bench', 'Bench Press');
      // Fake now: Tue 10 Nov 2026, 11:00. Weeks start on Monday.
      final DateTime fakeNow = DateTime(2026, 11, 10, 11);
      await insertWorkoutWithSet(
        workoutId: 'lastMon',
        exerciseId: 'bench',
        startedAt: DateTime(2026, 11, 2, 18),
        weightKg: 100,
        reps: 1,
      );
      await insertWorkoutWithSet(
        workoutId: 'lastThu',
        exerciseId: 'bench',
        startedAt: DateTime(2026, 11, 5, 18),
        weightKg: 200,
        reps: 1,
      );
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sharedPreferencesProvider
              .overrideWithValue(await SharedPreferences.getInstance()),
          clockProvider.overrideWithValue(() => fakeNow),
        ],
      );
      addTearDown(container.dispose);
      container.listen(dashboardWeekSnapshotProvider, (_, __) {});

      final WeekSnapshot week =
          await container.read(dashboardWeekSnapshotProvider.future);
      expect(week.volumeKg, 0);
      // All of last week is Monday and Thursday...
      expect(week.previousVolumeKg, 300);
      // ...but by Tuesday 11:00 last week only Monday had happened.
      expect(week.previousToDateVolumeKg, 100);
    });
  });

  group('the streak tile', () {
    Future<ProviderContainer> containerAt(DateTime now) async {
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
      container.listen(dashboardStreakWeeksProvider, (_, __) {});
      return container;
    }

    Future<void> mondays(String prefix, DateTime first, int weeks) async {
      for (int i = 0; i < weeks; i++) {
        await insertWorkoutWithSet(
          workoutId: '$prefix$i',
          exerciseId: 'bench',
          startedAt: DateTime(first.year, first.month, first.day + 7 * i, 18),
          weightKg: 100,
          reps: 1,
        );
      }
    }

    test('counts past the eight weeks the week card looks at', () async {
      await seedExercise('bench', 'Bench Press');
      // Twenty Mondays in a row, the last one yesterday (Tue 10 Nov 2026).
      await mondays('w', DateTime(2026, 6, 29), 20);
      final ProviderContainer container =
          await containerAt(DateTime(2026, 11, 10, 11));

      expect(await container.read(dashboardStreakWeeksProvider.future), 20,
          reason: 'it read 8 when counted from the hero window');
    });

    test('a week without training ends it, however long it was', () async {
      await seedExercise('bench', 'Bench Press');
      // Twelve weeks (20 Jul to 5 Oct), the week of 12 Oct off, then four.
      await mondays('old', DateTime(2026, 7, 20), 12);
      await mondays('new', DateTime(2026, 10, 19), 4);
      final ProviderContainer container =
          await containerAt(DateTime(2026, 11, 10, 11));

      expect(await container.read(dashboardStreakWeeksProvider.future), 4);
    });

    test('nothing logged is no streak', () async {
      final ProviderContainer container =
          await containerAt(DateTime(2026, 11, 10, 11));

      expect(await container.read(dashboardStreakWeeksProvider.future), 0);
    });
  });
}
