import '../../../core/database/daos/workout_dao.dart';

enum InsightSeverity { actionable, negative, positive }

enum InsightTarget { strength, volume, consistency, balance }

enum InsightKind {
  strengthChange,
  consistencySlipping,
  volumeTrendingDown,
  personalRecords,
  neglectedMuscle,
}

enum InsightDirection { up, down }

/// Locale-neutral data for one ranked progress conclusion.
///
/// User-facing sentences are built in the presentation layer so each locale
/// can control word order, grammar, and plural forms independently.
class ProgressInsight {
  const ProgressInsight({
    required this.severity,
    required this.target,
    required this.kind,
    this.subjectName,
    this.direction,
    this.percentage,
    this.currentBestKg,
    this.averageSessionsPerWeek,
    this.count,
  });

  final InsightSeverity severity;
  final InsightTarget target;
  final InsightKind kind;
  final String? subjectName;
  final InsightDirection? direction;
  final int? percentage;
  final double? currentBestKg;
  final double? averageSessionsPerWeek;
  final int? count;
}

/// Builds a small, ranked set of conclusions from already-loaded analytics.
/// Every rule has a data threshold so sparse history stays silent.
List<ProgressInsight> buildProgressInsights({
  required List<StrengthChange> strengthChanges,
  required List<WeeklyVolume> volume,
  required List<WorkoutFrequency> frequency,
  required List<MuscleGroupVolume> currentMuscleVolume,
  required List<MuscleGroupVolume> previousMuscleVolume,
  int recentPersonalRecords = 0,
}) {
  final insights = <ProgressInsight>[];

  final movers = strengthChanges.where((row) => row.change != null).toList();
  if (movers.length >= 2) {
    movers.sort((a, b) => b.change!.abs().compareTo(a.change!.abs()));
    final mover = movers.first;
    final change = mover.change!;
    insights.add(
      ProgressInsight(
        severity:
            change < 0 ? InsightSeverity.negative : InsightSeverity.positive,
        target: InsightTarget.strength,
        kind: InsightKind.strengthChange,
        subjectName: mover.exerciseName,
        direction: change < 0 ? InsightDirection.down : InsightDirection.up,
        percentage: (change.abs() * 100).round(),
        currentBestKg: mover.currentBestKg,
      ),
    );
  }

  // `frequency` is zero-filled from the selected range's nominal start
  // (see `WorkoutDao._fillWeekGaps`), so it can contain weeks that
  // pre-date the user's first-ever workout for anyone whose training
  // history is shorter than the range. Averaging over those inflates
  // "slipping" for someone who simply hasn't been training as long as a
  // 3- or 12-month range — mirrors the same clamp in
  // `calculateConsistency`. Assumed ascending by weekStart, matching every
  // DAO stream this function is fed from; not re-sorted here so a caller
  // passing rows in DAO order never risks an unstable sort on tied weeks.
  final firstActiveWeek =
      frequency.indexWhere((week) => week.workoutCount > 0);
  final eligibleWeeks = firstActiveWeek == -1
      ? const <WorkoutFrequency>[]
      : frequency.sublist(firstActiveWeek);
  if (eligibleWeeks.length >= 4) {
    final active = eligibleWeeks.where((week) => week.workoutCount > 0).length;
    final average =
        eligibleWeeks.fold<int>(0, (sum, week) => sum + week.workoutCount) /
            eligibleWeeks.length;
    if (active >= 2 && average < 1) {
      insights.add(
        ProgressInsight(
          severity: InsightSeverity.negative,
          target: InsightTarget.consistency,
          kind: InsightKind.consistencySlipping,
          averageSessionsPerWeek: average,
        ),
      );
    }
  }

  if (volume.length >= 4) {
    final midpoint = volume.length ~/ 2;
    final earlier = volume
        .take(midpoint)
        .fold<double>(0, (sum, row) => sum + row.totalVolumeKg);
    final recent = volume
        .skip(midpoint)
        .fold<double>(0, (sum, row) => sum + row.totalVolumeKg);
    if (earlier > 0 && recent < earlier * .8) {
      insights.add(
        ProgressInsight(
          severity: InsightSeverity.negative,
          target: InsightTarget.volume,
          kind: InsightKind.volumeTrendingDown,
          percentage: ((1 - recent / earlier) * 100).round(),
        ),
      );
    }
  }

  if (recentPersonalRecords >= 2) {
    insights.add(
      ProgressInsight(
        severity: InsightSeverity.positive,
        target: InsightTarget.strength,
        kind: InsightKind.personalRecords,
        count: recentPersonalRecords,
      ),
    );
  }

  final neglected =
      previousMuscleVolume.where((old) => old.totalVolumeKg > 0).where((old) {
    final current = currentMuscleVolume
        .where((row) => row.muscleId == old.muscleId)
        .fold<double>(0, (sum, row) => sum + row.totalVolumeKg);
    return current < old.totalVolumeKg * .1;
  }).toList();
  if (neglected.isNotEmpty) {
    final group = neglected.first;
    insights.add(
      ProgressInsight(
        severity: InsightSeverity.actionable,
        target: InsightTarget.balance,
        kind: InsightKind.neglectedMuscle,
        subjectName: group.muscleName,
      ),
    );
  }

  const severityRank = {
    InsightSeverity.actionable: 0,
    InsightSeverity.negative: 1,
    InsightSeverity.positive: 2,
  };
  insights.sort(
    (a, b) => severityRank[a.severity]!.compareTo(severityRank[b.severity]!),
  );
  return insights.take(4).toList();
}
