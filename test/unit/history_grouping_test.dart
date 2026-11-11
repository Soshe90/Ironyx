import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/tables/workouts.dart';
import 'package:ironyx/features/tracker/domain/history_grouping.dart';

/// The Workouts history: one month heading over that month's rows.
void main() {
  Workout at(String id, DateTime startedAt, double kg) => Workout(
        id: id,
        startedAt: startedAt,
        totalVolumeKg: kg,
        schemaVersion: 1,
      );

  String describe(HistoryEntry e) => switch (e) {
        MonthEntry(:final month, :final workoutCount, :final volumeKg) =>
          'month ${month.year}-${month.month} $workoutCount ${volumeKg.round()}',
        WorkoutEntry(:final workout, :final firstInMonth) =>
          '${workout.id}${firstInMonth ? ' first' : ''}',
      };

  test('no workouts, no entries', () {
    expect(groupHistoryByMonth(const <Workout>[]), isEmpty);
  });

  test('a heading per month, newest first, with its count and volume', () {
    final List<HistoryEntry> entries = groupHistoryByMonth(<Workout>[
      at('nov9', DateTime(2026, 11, 9, 18), 300),
      at('nov4', DateTime(2026, 11, 4, 9), 200),
      at('oct31', DateTime(2026, 10, 31, 17), 500),
    ]);

    expect(entries.map(describe), <String>[
      'month 2026-11 2 500',
      'nov9 first',
      'nov4',
      'month 2026-10 1 500',
      'oct31 first',
    ]);
  });

  test('the same month of different years is two headings', () {
    final List<HistoryEntry> entries = groupHistoryByMonth(<Workout>[
      at('2026', DateTime(2026, 11, 1), 100),
      at('2025', DateTime(2025, 11, 1), 100),
    ]);

    expect(entries.whereType<MonthEntry>().map((MonthEntry m) => m.month),
        <DateTime>[DateTime(2026, 11), DateTime(2025, 11)]);
  });

  test('the first and last moments of a month stay in it', () {
    final List<HistoryEntry> entries = groupHistoryByMonth(<Workout>[
      at('last', DateTime(2026, 11, 30, 23, 59), 10),
      at('first', DateTime(2026, 11, 1, 0, 0), 20),
      at('before', DateTime(2026, 10, 31, 23, 59), 40),
    ]);

    expect(entries.map(describe), <String>[
      'month 2026-11 2 30',
      'last first',
      'first',
      'month 2026-10 1 40',
      'before first',
    ]);
  });
}
