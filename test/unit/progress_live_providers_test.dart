import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/body_metrics_dao.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/profile_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/services/clock.dart';
import 'package:ironyx/features/progress/domain/progress_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The Progress tab stays alive in the shell, so its figures have to follow
/// the data and the date while it is open rather than whatever they were
/// when it was first built.
void main() {
  // LocalNow observes the app lifecycle through WidgetsBinding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late DateTime fakeNow;

  setUp(() async {
    database = AppDatabase.forTesting();
    fakeNow = DateTime(2026, 11, 10, 12);
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

  Future<void> logSquat(String id, DateTime startedAt, double kg) =>
      WorkoutDao(database).insertWorkout(
        WorkoutsTableCompanion.insert(
          id: id,
          startedAt: startedAt,
          endedAt: Value(startedAt.add(const Duration(minutes: 45))),
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

  Future<void> weighIn(String id, DateTime date, double kg) =>
      BodyMetricsDao(database).upsert(
        BodyMetricsTableCompanion.insert(id: id, date: date, weightKg: kg),
      );

  Future<ProviderContainer> container() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final ProviderContainer c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
        clockProvider.overrideWithValue(() => fakeNow),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Moves the fake clock and tells LocalNow, as a resume or a day
  /// boundary would.
  void advance(ProviderContainer c, Duration by) {
    fakeNow = fakeNow.add(by);
    c.read(localNowProvider.notifier).refresh();
  }

  /// Re-reads [read] until [matches] holds: a Drift stream emits a write
  /// asynchronously, so the first read after one can still be the old value.
  Future<T> eventually<T>(
    Future<T> Function() read,
    bool Function(T value) matches,
  ) async {
    T value = await read();
    for (int i = 0; i < 50 && !matches(value); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      value = await read();
    }
    return value;
  }

  group('relative strength', () {
    test('follows a new weigh-in', () async {
      await logSquat('w1', fakeNow.subtract(const Duration(days: 3)), 160);
      await weighIn('bm1', fakeNow.subtract(const Duration(days: 2)), 80);
      final ProviderContainer c = await container();
      final provider = relativeStrengthsProvider(ProgressRange.quarter);
      c.listen(provider, (_, __) {});

      final before = await c.read(provider.future);
      expect(before.single.ratio, closeTo(2.0, 0.0001));

      await weighIn('bm2', fakeNow, 100);

      final after = await eventually(
        () => c.read(provider.future),
        (rows) => rows.isNotEmpty && rows.single.bodyWeightKg == 100,
      );
      expect(after.single.ratio, closeTo(1.6, 0.0001));
    });

    test('drops a weigh-in once it is over 30 days old, tab still open',
        () async {
      await logSquat('w1', fakeNow.subtract(const Duration(days: 3)), 160);
      await weighIn('bm1', fakeNow.subtract(const Duration(days: 25)), 80);
      final ProviderContainer c = await container();
      final provider = relativeStrengthsProvider(ProgressRange.year);
      c.listen(provider, (_, __) {});

      expect(await c.read(provider.future), isNotEmpty);

      advance(c, const Duration(days: 10));

      expect(await c.read(provider.future), isEmpty);
    });
  });

  test('adherence follows a change of weekly target', () async {
    await logSquat('w1', fakeNow.subtract(const Duration(days: 8)), 100);
    final ProviderContainer c = await container();
    final provider = consistencySummaryProvider(ProgressRange.month);
    c.listen(provider, (_, __) {});

    expect((await c.read(provider.future)).targetSessionsPerWeek, 3);

    await ProfileDao(database).setWeeklySessionTarget(1);

    final after = await eventually(
      () => c.read(provider.future),
      (s) => s.targetSessionsPerWeek == 1,
    );
    expect(after.targetSessionsPerWeek, 1);
  });

  group('the range window', () {
    test('is anchored to LocalNow', () async {
      final ProviderContainer c = await container();
      final provider = progressSinceProvider(ProgressRange.twoWeeks);
      c.listen(provider, (_, __) {});

      expect(c.read(provider), fakeNow.subtract(const Duration(days: 14)));
      advance(c, const Duration(days: 1));
      expect(c.read(provider), fakeNow.subtract(const Duration(days: 14)));
      expect(c.read(progressSinceProvider(ProgressRange.all)), isNull);
    });

    test('moves on while the tab stays open', () async {
      // Ten days old today; seventeen once a week has passed, which is
      // outside "2W". Captured at first build, it stayed listed.
      await logSquat('w1', fakeNow.subtract(const Duration(days: 10)), 100);
      final ProviderContainer c = await container();
      final provider = strengthChangeProvider(ProgressRange.twoWeeks);
      c.listen(provider, (_, __) {});

      expect(await c.read(provider.future), hasLength(1));

      advance(c, const Duration(days: 7));

      expect(await c.read(provider.future), isEmpty);
    });
  });

  test('adherence after a break counts the weeks of the break', () async {
    // Fake now is Tue 10 Nov 2026. "1M" starts Sun 11 Oct, inside the week
    // of Mon 5 Oct. Trained in April, then nothing until Sat 7 Nov.
    await logSquat('april', DateTime(2026, 4, 1, 18), 100);
    await logSquat('back', DateTime(2026, 11, 7, 10), 100);
    final ProviderContainer c = await container();
    final provider = consistencySummaryProvider(ProgressRange.month);
    c.listen(provider, (_, __) {});

    final summary = await c.read(provider.future);
    // 12, 19 and 26 Oct and 2 Nov. Left out: the partial week of 5 Oct and
    // this unfinished week, neither of which met the target of 3.
    expect(summary.eligibleWeeks, 4);
    expect(summary.hitTargetWeeks, 0);
  });

  group('the streaks', () {
    test('are not capped by the range', () async {
      // Twenty Mondays in a row, the last one yesterday (now is Tue 10 Nov
      // 2026). "1M" holds five of them.
      for (int i = 0; i < 20; i++) {
        await logSquat('w$i', DateTime(2026, 6, 29 + 7 * i, 18), 100);
      }
      final ProviderContainer c = await container();
      final provider = consistencySummaryProvider(ProgressRange.month);
      c.listen(provider, (_, __) {});

      final summary = await c.read(provider.future);
      expect(summary.currentStreakWeeks, 20, reason: 'it read 5 on "1M"');
      expect(summary.longestStreakWeeks, 20);
    });

    test('the longest can be from before the range', () async {
      // Ten weeks from 6 Apr, then only this week's Monday.
      for (int i = 0; i < 10; i++) {
        await logSquat('old$i', DateTime(2026, 4, 6 + 7 * i, 18), 100);
      }
      await logSquat('now', DateTime(2026, 11, 9, 18), 100);
      final ProviderContainer c = await container();
      final provider = consistencySummaryProvider(ProgressRange.month);
      c.listen(provider, (_, __) {});

      final summary = await c.read(provider.future);
      expect(summary.currentStreakWeeks, 1);
      expect(summary.longestStreakWeeks, 10);
    });
  });
}
