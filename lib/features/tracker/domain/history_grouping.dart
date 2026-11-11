import '../../../core/database/tables/workouts.dart';

/// One line of the history list: a month heading or a workout row.
sealed class HistoryEntry {
  const HistoryEntry();
}

final class MonthEntry extends HistoryEntry {
  const MonthEntry(this.month, this.workoutCount, this.volumeKg);

  final DateTime month;
  final int workoutCount;
  final double volumeKg;
}

final class WorkoutEntry extends HistoryEntry {
  const WorkoutEntry(this.workout, {required this.firstInMonth});

  final Workout workout;
  final bool firstInMonth;
}

/// Groups the newest-first list by month: a [MonthEntry] (its workout
/// count and volume) before that month's [WorkoutEntry]s.
///
/// One heading per month replaced a heading above every row: with about
/// one workout a day, half the list was headings, and the day now lives in
/// each row's date tile. Pure, so it is unit-tested on its own; it ran
/// inside the list's widget.
List<HistoryEntry> groupHistoryByMonth(List<Workout> workouts) {
  final List<HistoryEntry> entries = <HistoryEntry>[];
  int start = 0;
  while (start < workouts.length) {
    final DateTime first = workouts[start].startedAt;
    int end = start;
    double volume = 0;
    while (end < workouts.length &&
        workouts[end].startedAt.year == first.year &&
        workouts[end].startedAt.month == first.month) {
      volume += workouts[end].totalVolumeKg;
      end++;
    }
    entries.add(
      MonthEntry(DateTime(first.year, first.month), end - start, volume),
    );
    for (int i = start; i < end; i++) {
      entries.add(WorkoutEntry(workouts[i], firstInMonth: i == start));
    }
    start = end;
  }
  return entries;
}
