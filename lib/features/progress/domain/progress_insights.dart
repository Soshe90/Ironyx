import '../../../core/database/daos/workout_dao.dart';

enum InsightSeverity { actionable, negative, positive }

enum InsightTarget { strength, volume, consistency, balance }

class ProgressInsight {
  const ProgressInsight(
      {required this.severity,
      required this.headline,
      required this.supportingFigure,
      required this.target});
  final InsightSeverity severity;
  final String headline;
  final String supportingFigure;
  final InsightTarget target;
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
    insights.add(ProgressInsight(
      severity:
          change < 0 ? InsightSeverity.negative : InsightSeverity.positive,
      headline:
          '${mover.exerciseName} is ${change < 0 ? 'down' : 'up'} ${(change.abs() * 100).round()}%',
      supportingFigure: '${mover.currentBestKg.toStringAsFixed(1)} kg e1RM',
      target: InsightTarget.strength,
    ));
  }

  if (frequency.length >= 4) {
    final active = frequency.where((week) => week.workoutCount > 0).length;
    final average =
        frequency.fold<int>(0, (sum, week) => sum + week.workoutCount) /
            frequency.length;
    if (active >= 2 && average < 1) {
      insights.add(ProgressInsight(
        severity: InsightSeverity.negative,
        headline: 'Training consistency is slipping',
        supportingFigure: '${average.toStringAsFixed(1)} sessions/week',
        target: InsightTarget.consistency,
      ));
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
      insights.add(ProgressInsight(
        severity: InsightSeverity.negative,
        headline: 'Weekly volume is trending down',
        supportingFigure:
            '${((recent / earlier - 1) * 100).round()}% vs earlier weeks',
        target: InsightTarget.volume,
      ));
    }
  }

  if (recentPersonalRecords >= 2) {
    insights.add(ProgressInsight(
      severity: InsightSeverity.positive,
      headline: 'New personal records are stacking up',
      supportingFigure: '$recentPersonalRecords recent PRs',
      target: InsightTarget.strength,
    ));
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
    insights.add(ProgressInsight(
      severity: InsightSeverity.actionable,
      headline: '${group.muscleName} has been neglected',
      supportingFigure: 'under 10% of the previous volume',
      target: InsightTarget.balance,
    ));
  }

  final severityRank = {
    InsightSeverity.actionable: 0,
    InsightSeverity.negative: 1,
    InsightSeverity.positive: 2
  };
  insights.sort(
      (a, b) => severityRank[a.severity]!.compareTo(severityRank[b.severity]!));
  return insights.take(4).toList();
}
