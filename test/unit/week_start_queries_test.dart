import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/core/formatters/week_start.dart';

/// The weekly and weekday queries, grouped by the first day of the week
/// chosen in Settings and by the device's time rather than UTC.
///
/// Reference calendar, January 2026: Fri 2, Sat 3, Sun 4, Mon 5, Fri 9,
/// Sat 10, Sun 11, Mon 12. All workouts are given as UTC instants and the
/// offset is passed explicitly, so these read the same in any time zone.
void main() {
  late AppDatabase database;
  late WorkoutDao dao;

  setUp(() async {
    database = AppDatabase.forTesting();
    dao = WorkoutDao(database);
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

  Future<void> log(String id, DateTime startedAt, {double volumeKg = 500}) =>
      dao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: id,
          startedAt: startedAt,
          endedAt: Value(startedAt.add(const Duration(hours: 1))),
          totalVolumeKg: Value(volumeKg),
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

  /// Fri 9, Sat 10, Sun 11 and Mon 12 Jan 2026, all at noon UTC.
  Future<void> logFridayToMonday() async {
    await log('fri', DateTime.utc(2026, 1, 9, 12), volumeKg: 100);
    await log('sat', DateTime.utc(2026, 1, 10, 12), volumeKg: 200);
    await log('sun', DateTime.utc(2026, 1, 11, 12), volumeKg: 400);
    await log('mon', DateTime.utc(2026, 1, 12, 12), volumeKg: 800);
  }

  group('weekly buckets follow the first day of the week', () {
    // The same four workouts, split three ways.
    final Map<WeekStart, List<(DateTime, int, double)>> expected =
        <WeekStart, List<(DateTime, int, double)>>{
      WeekStart.monday: <(DateTime, int, double)>[
        (DateTime(2026, 1, 5), 3, 700), // Fri, Sat, Sun
        (DateTime(2026, 1, 12), 1, 800), // Mon
      ],
      WeekStart.sunday: <(DateTime, int, double)>[
        (DateTime(2026, 1, 4), 2, 300), // Fri, Sat
        (DateTime(2026, 1, 11), 2, 1200), // Sun, Mon
      ],
      WeekStart.saturday: <(DateTime, int, double)>[
        (DateTime(2026, 1, 3), 1, 100), // Fri
        (DateTime(2026, 1, 10), 3, 1400), // Sat, Sun, Mon
      ],
    };

    for (final WeekStart start in WeekStart.values) {
      test('frequency and volume, week starting ${start.name}', () async {
        await logFridayToMonday();

        final frequency =
            await dao.watchWorkoutFrequency(weekStart: start).first;
        final volume = await dao.watchWeeklyVolume(weekStart: start).first;

        for (int i = 0; i < 2; i++) {
          final (DateTime week, int count, double kg) = expected[start]![i];
          expect(frequency[i].weekStart, week, reason: 'bucket $i');
          expect(frequency[i].workoutCount, count, reason: 'bucket $i');
          expect(volume[i].weekStart, week, reason: 'bucket $i');
          expect(volume[i].totalVolumeKg, kg, reason: 'bucket $i');
        }
        // Nothing is counted twice or dropped by the regrouping.
        expect(
          frequency.fold<int>(0, (sum, f) => sum + f.workoutCount),
          4,
        );
        expect(
          volume.fold<double>(0, (sum, v) => sum + v.totalVolumeKg),
          1500,
        );
      });

      test('every bucket, filled or empty, starts on ${start.name}', () async {
        await logFridayToMonday();

        final frequency =
            await dao.watchWorkoutFrequency(weekStart: start).first;

        // The series runs on to the current week, zero-filled.
        expect(frequency.length, greaterThan(2));
        for (int i = 0; i < frequency.length; i++) {
          final DateTime week = frequency[i].weekStart;
          expect(week.weekday, start.weekday, reason: 'bucket $i');
          expect(week.hour, 0, reason: 'bucket $i');
          if (i == 0) continue;
          final DateTime before = frequency[i - 1].weekStart;
          expect(
            DateTime.utc(week.year, week.month, week.day)
                .difference(
                  DateTime.utc(before.year, before.month, before.day),
                )
                .inDays,
            7,
            reason: 'bucket $i is not a week after bucket ${i - 1}',
          );
        }
        expect(frequency.skip(2).every((f) => f.workoutCount == 0), isTrue);
      });
    }

    test('with nothing chosen the buckets are the Monday ones they always were',
        () async {
      await logFridayToMonday();

      final frequency = await dao.watchWorkoutFrequency().first;

      expect(frequency[0].weekStart, DateTime(2026, 1, 5));
      expect(frequency[0].workoutCount, 3);
      expect(frequency[1].weekStart, DateTime(2026, 1, 12));
      expect(frequency[1].workoutCount, 1);
    });
  });

  group('weekly buckets follow the device time, not UTC', () {
    test('just after local midnight on a week\'s first day, east of UTC',
        () async {
      // Sat 10 Jan 21:30 UTC is Sun 11 Jan 00:30 at UTC+3.
      await log('late', DateTime.utc(2026, 1, 10, 21, 30));

      final utc =
          await dao.watchWorkoutFrequency(weekStart: WeekStart.sunday).first;
      final local = await dao
          .watchWorkoutFrequency(
            weekStart: WeekStart.sunday,
            utcOffset: const Duration(hours: 3),
          )
          .first;

      // In UTC it is still Saturday, the last day of the week before.
      expect(utc.first.weekStart, DateTime(2026, 1, 4));
      // For the person who logged it, it is Sunday: the new week.
      expect(local.first.weekStart, DateTime(2026, 1, 11));
      expect(local.first.workoutCount, 1);
    });

    test('late on a week\'s last evening, west of UTC', () async {
      // Sun 11 Jan 02:00 UTC is Sat 10 Jan 18:00 at UTC−8.
      await log('evening', DateTime.utc(2026, 1, 11, 2));

      final utc =
          await dao.watchWeeklyVolume(weekStart: WeekStart.sunday).first;
      final local = await dao
          .watchWeeklyVolume(
            weekStart: WeekStart.sunday,
            utcOffset: const Duration(hours: -8),
          )
          .first;

      expect(utc.first.weekStart, DateTime(2026, 1, 11));
      expect(local.first.weekStart, DateTime(2026, 1, 4));
      expect(local.first.totalVolumeKg, 500);
    });

    test('half-hour offsets count', () async {
      // Fri 9 Jan 18:45 UTC is Sat 10 Jan 00:15 at UTC+5:30.
      await log('india', DateTime.utc(2026, 1, 9, 18, 45));

      final local = await dao
          .watchWorkoutFrequency(
            weekStart: WeekStart.saturday,
            utcOffset: const Duration(hours: 5, minutes: 30),
          )
          .first;

      expect(local.first.weekStart, DateTime(2026, 1, 10));
    });

    test('two workouts either side of local midnight split into two weeks',
        () async {
      // 23:30 Sat and 00:30 Sun at UTC+3.
      await log('before', DateTime.utc(2026, 1, 10, 20, 30));
      await log('after', DateTime.utc(2026, 1, 10, 21, 30));

      final local = await dao
          .watchWorkoutFrequency(
            weekStart: WeekStart.sunday,
            utcOffset: const Duration(hours: 3),
          )
          .first;

      expect(local[0].weekStart, DateTime(2026, 1, 4));
      expect(local[0].workoutCount, 1);
      expect(local[1].weekStart, DateTime(2026, 1, 11));
      expect(local[1].workoutCount, 1);
    });
  });

  group('gap filling uses the same weeks as the query', () {
    test('a since bound starts the series at its own week', () async {
      await log('mon', DateTime.utc(2026, 1, 12, 12));

      // Wed 7 Jan: in the week of Sat 3 Jan when weeks start on Saturday.
      final frequency = await dao
          .watchWorkoutFrequency(
            since: DateTime.utc(2026, 1, 7),
            weekStart: WeekStart.saturday,
          )
          .first;

      expect(frequency[0].weekStart, DateTime(2026, 1, 3));
      expect(frequency[0].workoutCount, 0);
      expect(frequency[1].weekStart, DateTime(2026, 1, 10));
      expect(frequency[1].workoutCount, 1);
    });

    test('the since bound\'s week is found in device time too', () async {
      await log('sun', DateTime.utc(2026, 1, 18, 12));

      // Sat 10 Jan 21:30 UTC: still the week of Sun 4 Jan in UTC, already
      // the week of Sun 11 Jan at UTC+3.
      final DateTime since = DateTime.utc(2026, 1, 10, 21, 30);
      final utc = await dao
          .watchWorkoutFrequency(since: since, weekStart: WeekStart.sunday)
          .first;
      final local = await dao
          .watchWorkoutFrequency(
            since: since,
            weekStart: WeekStart.sunday,
            utcOffset: const Duration(hours: 3),
          )
          .first;

      expect(utc.first.weekStart, DateTime(2026, 1, 4));
      expect(local.first.weekStart, DateTime(2026, 1, 11));
      // Each trained week appears once, on a bucket the query produced.
      expect(local.where((f) => f.workoutCount > 0), hasLength(1));
      expect(
        local.firstWhere((f) => f.workoutCount > 0).weekStart,
        DateTime(2026, 1, 18),
      );
    });

    test('the series ends on the current week for each first day', () async {
      await log('old', DateTime.utc(2026, 1, 12, 12));

      for (final WeekStart start in WeekStart.values) {
        final frequency =
            await dao.watchWorkoutFrequency(weekStart: start).first;
        final DateTime last = frequency.last.weekStart;
        final DateTime nowUtc = DateTime.now().toUtc();
        final int daysAgo = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day)
            .difference(DateTime.utc(last.year, last.month, last.day))
            .inDays;

        expect(last.weekday, start.weekday);
        expect(daysAgo, inInclusiveRange(0, 6), reason: '$start');
      }
    });

    test('an empty result stays empty for every first day', () async {
      for (final WeekStart start in WeekStart.values) {
        expect(await dao.watchWeeklyVolume(weekStart: start).first, isEmpty);
        expect(
          await dao.watchWorkoutFrequency(weekStart: start).first,
          isEmpty,
        );
      }
    });
  });

  group('weekday distribution', () {
    test('lists the days in the order the week runs', () async {
      await logFridayToMonday();

      for (final WeekStart start in WeekStart.values) {
        final days = await dao.watchWeekdayDistribution(weekStart: start).first;

        expect(days.map((d) => d.weekday), start.weekdays, reason: '$start');
        // The counts travel with their day, not with their position.
        for (final day in days) {
          final bool trained = <int>[
            DateTime.friday,
            DateTime.saturday,
            DateTime.sunday,
            DateTime.monday,
          ].contains(day.weekday);
          expect(day.workoutCount, trained ? 1 : 0, reason: '$start, $day');
        }
      }
    });

    test('an unfinished workout is not counted, whatever the first day',
        () async {
      await dao.insertWorkout(
        WorkoutsTableCompanion.insert(
          id: 'open',
          startedAt: DateTime.utc(2026, 1, 10, 12),
        ),
        const [],
        const [],
      );

      for (final WeekStart start in WeekStart.values) {
        expect(
          await dao.watchWorkoutFrequency(weekStart: start).first,
          isEmpty,
        );
      }
    });
  });
}
