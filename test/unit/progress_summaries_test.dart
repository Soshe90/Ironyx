import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/workout_dao.dart';
import 'package:ironyx/features/progress/domain/progress_summaries.dart';

void main() {
  final DateTime monday = DateTime.parse('2026-01-05');
  DateTime week(int i) => monday.add(Duration(days: i * 7));

  group('summarizeWeeklyVolume', () {
    test('totals every week and counts only the trained ones', () {
      final r = summarizeWeeklyVolume([
        WeeklyVolume(weekStart: week(0), totalVolumeKg: 1000),
        WeeklyVolume(weekStart: week(1), totalVolumeKg: 0),
        WeeklyVolume(weekStart: week(2), totalVolumeKg: 500.5),
      ]);
      expect(r.totalKg, 1500.5);
      expect(r.activeWeeks, 2);
    });

    test('is zero for an empty series', () {
      final r = summarizeWeeklyVolume(const []);
      expect(r.totalKg, 0);
      expect(r.activeWeeks, 0);
    });
  });

  group('summarizeWeeklyFrequency', () {
    test('totals workouts and counts only the trained weeks', () {
      final r = summarizeWeeklyFrequency([
        WorkoutFrequency(weekStart: week(0), workoutCount: 3),
        WorkoutFrequency(weekStart: week(1), workoutCount: 0),
        WorkoutFrequency(weekStart: week(2), workoutCount: 1),
      ]);
      expect(r.workouts, 4);
      expect(r.activeWeeks, 2);
    });

    test('is zero for an empty series', () {
      final r = summarizeWeeklyFrequency(const []);
      expect(r.workouts, 0);
      expect(r.activeWeeks, 0);
    });
  });

  group('averageSessionRpe', () {
    SessionRpe rpe(String id, double value, [int sets = 1]) => SessionRpe(
          workoutId: id,
          date: monday,
          averageRpe: value,
          ratedSetCount: sets,
          volumeKg: 1000,
        );

    test('with the same number of rated sets, is the plain mean', () {
      expect(
        averageSessionRpe([rpe('a', 7), rpe('b', 8), rpe('c', 9.5)]),
        closeTo(8.1667, 0.0001),
      );
    });

    test('weights each session by the sets it rated', () {
      // One all-out set against twenty at 7: 7.14, not 8.5.
      expect(
        averageSessionRpe([rpe('a', 10, 1), rpe('b', 7, 20)]),
        closeTo((10 + 7 * 20) / 21, 0.0001),
      );
    });

    test('is null without sessions, or with nothing rated', () {
      expect(averageSessionRpe(const []), isNull);
      expect(averageSessionRpe([rpe('a', 8, 0)]), isNull);
    });
  });

  group('summarizeRest', () {
    SessionRest rest(String id, double seconds, int count) => SessionRest(
          workoutId: id,
          date: monday,
          averageRestSeconds: seconds,
          recordedSetCount: count,
        );

    test('weights each session by the rests it recorded', () {
      // One 300 s rest against twenty 60 s rests: 71.4 s, not 180 s.
      final r = summarizeRest([rest('a', 300, 1), rest('b', 60, 20)]);
      expect(r.restCount, 21);
      expect(r.averageSeconds, closeTo((300 + 60 * 20) / 21, 0.0001));
    });

    test('a session with no timed rests adds nothing', () {
      final r = summarizeRest([rest('a', 0, 0), rest('b', 90, 4)]);
      expect(r.restCount, 4);
      expect(r.averageSeconds, closeTo(90, 0.0001));
    });

    test('nothing timed is no average, not zero seconds', () {
      expect(summarizeRest(const []).averageSeconds, isNull);
      expect(summarizeRest([rest('a', 0, 0)]).averageSeconds, isNull);
    });
  });

  group('groupMuscleVolume', () {
    MuscleGroupVolume group(String id, double kg) =>
        MuscleGroupVolume(muscleId: id, muscleName: id, totalVolumeKg: kg);

    test('drops groups with no volume', () {
      final r = groupMuscleVolume(
        [group('chest', 500), group('core', 0), group('back', 300)],
        slots: 6,
        otherName: 'Other',
      );
      expect(r.groups.map((g) => g.muscleId), ['chest', 'back']);
      expect(r.total, 800);
      expect(r.largest, 500);
    });

    test('exactly as many groups as slots has no Other row', () {
      final r = groupMuscleVolume(
        [group('a', 3), group('b', 2), group('c', 1)],
        slots: 3,
        otherName: 'Other',
      );
      expect(r.groups.map((g) => g.muscleId), ['a', 'b', 'c']);
    });

    test('folds everything past the slots into one Other row', () {
      final r = groupMuscleVolume(
        [
          group('a', 400),
          group('b', 300),
          group('c', 200),
          group('d', 100),
          group('zero', 0),
        ],
        slots: 2,
        otherName: 'Autres',
      );
      expect(r.groups.map((g) => g.muscleId), ['a', 'b', otherMuscleGroupId]);
      expect(r.groups.last.muscleName, 'Autres');
      expect(r.groups.last.totalVolumeKg, 300);
      // Shares still add up to the whole.
      expect(r.total, 1000);
      expect(r.largest, 400);
    });

    test('Other can be the largest row', () {
      final r = groupMuscleVolume(
        [group('a', 100), group('b', 90), group('c', 90)],
        slots: 1,
        otherName: 'Other',
      );
      expect(r.largest, 180);
    });

    test('nothing trained is empty', () {
      final r = groupMuscleVolume(
        [group('a', 0)],
        slots: 6,
        otherName: 'Other',
      );
      expect(r.groups, isEmpty);
      expect(r.total, 0);
      expect(r.largest, 0);
    });
  });

  group('muscleWeeklySeries', () {
    WeeklyMuscleGroupVolume row(int w, String id, double kg) =>
        WeeklyMuscleGroupVolume(
          weekStart: week(w),
          muscleId: id,
          muscleName: id,
          totalVolumeKg: kg,
        );
    List<WeeklyVolume> axisOf(int weeks) => <WeeklyVolume>[
          for (int i = 0; i < weeks; i++)
            WeeklyVolume(weekStart: week(i), totalVolumeKg: 1),
        ];

    test('puts the group on every week of the axis, zero where untrained', () {
      final r = muscleWeeklySeries(
        muscleId: 'chest',
        rows: [row(0, 'chest', 100), row(2, 'chest', 300)],
        axis: axisOf(4),
      );
      expect(r.weeks, [week(0), week(1), week(2), week(3)]);
      expect(r.values, [100, 0, 300, 0]);
    });

    test('ignores other groups and adds up repeated rows', () {
      final r = muscleWeeklySeries(
        muscleId: 'chest',
        rows: [
          row(0, 'chest', 100),
          row(0, 'chest', 50),
          row(0, 'back', 999),
        ],
        axis: axisOf(1),
      );
      expect(r.values, [150]);
    });

    test('without an axis, uses the group\'s own weeks in order', () {
      final r = muscleWeeklySeries(
        muscleId: 'chest',
        rows: [row(3, 'chest', 30), row(1, 'chest', 10)],
        axis: const [],
      );
      expect(r.weeks, [week(1), week(3)]);
      expect(r.values, [10, 30]);
    });

    test('nothing for the group and no axis is empty', () {
      final r = muscleWeeklySeries(
        muscleId: 'chest',
        rows: [row(0, 'back', 100)],
        axis: const [],
      );
      expect(r.weeks, isEmpty);
      expect(r.values, isEmpty);
    });
  });
}
