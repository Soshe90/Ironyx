import '../../../core/database/daos/workout_dao.dart';
import '../../../core/formatters/date_formatters.dart';
import '../../../core/formatters/week_start.dart';
import 'consistency_calculators.dart';

enum InsightSeverity { actionable, negative, positive }

enum InsightTarget { strength, volume, consistency, balance }

enum InsightKind {
  strengthChange,
  consistencySlipping,
  volumeTrendingDown,
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
    this.subjectId,
    this.subjectName,
    this.direction,
    this.percentage,
    this.currentBestKg,
    this.averageSessionsPerWeek,
  });

  final InsightSeverity severity;
  final InsightTarget target;
  final InsightKind kind;

  /// Id of the exercise or muscle group [subjectName] names, so the
  /// presentation layer can show the name in the user's language. The name
  /// itself is the stored English one.
  final String? subjectId;
  final String? subjectName;
  final InsightDirection? direction;
  final int? percentage;
  final double? currentBestKg;
  final double? averageSessionsPerWeek;
}

/// Smallest change in a lift's estimated 1RM that the insights mention.
///
/// The estimate is printed to the whole kilogram (about 1% of a 100 kg
/// lift) and moves a few percent between ordinary sessions, so "Bench is
/// up 1%" was rounding and day-to-day noise presented as a finding.
/// Reasoned, not measured: tune it if real data says otherwise.
const double minInsightStrengthChange = 0.03;

/// Builds a small, ranked set of conclusions from already-loaded analytics.
/// Every rule has a data threshold so sparse history stays silent.
///
/// Personal records are not among them: the hero card states the count
/// directly above, and an insight repeating it said nothing new.
///
/// [weekStart] and [utcOffset] have to be the ones the weekly series were
/// bucketed with, so that the week in progress (found from [now]) names a
/// bucket that exists in them. The weekly rules leave that week out: it
/// is unfinished, so on a Monday it held almost nothing and every series
/// looked as if it had just fallen off.
List<ProgressInsight> buildProgressInsights({
  required List<StrengthChange> strengthChanges,
  required List<WeeklyVolume> volume,
  required List<WorkoutFrequency> frequency,
  required List<MuscleGroupVolume> currentMuscleVolume,
  required List<MuscleGroupVolume> previousMuscleVolume,
  WeekStart weekStart = WeekStart.monday,
  Duration utcOffset = Duration.zero,
  DateTime? now,
  DateTime? rangeStart,
  DateTime? firstWorkoutAt,
}) {
  final insights = <ProgressInsight>[];
  final DateTime currentWeek = DateFormatters.weekBucketStart(
    now ?? DateTime.now(),
    weekStart: weekStart,
    utcOffset: utcOffset,
  );
  final List<WeeklyVolume> finishedVolume = <WeeklyVolume>[
    for (final w in volume)
      if (w.weekStart != currentWeek) w,
  ];
  final List<WorkoutFrequency> finishedFrequency = <WorkoutFrequency>[
    for (final w in frequency)
      if (w.weekStart != currentWeek) w,
  ];

  final movers = strengthChanges.where((row) => row.change != null).toList();
  if (movers.length >= 2) {
    movers.sort((a, b) => b.change!.abs().compareTo(a.change!.abs()));
    final mover = movers.first;
    final change = mover.change!;
    // The biggest mover is below the threshold, so every lift is.
    if (change.abs() >= minInsightStrengthChange) {
      insights.add(
        ProgressInsight(
          severity:
              change < 0 ? InsightSeverity.negative : InsightSeverity.positive,
          target: InsightTarget.strength,
          kind: InsightKind.strengthChange,
          subjectId: mover.exerciseId,
          subjectName: mover.exerciseName,
          direction: change < 0 ? InsightDirection.down : InsightDirection.up,
          percentage: (change.abs() * 100).round(),
          currentBestKg: mover.currentBestKg,
        ),
      );
    }
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
  //
  // Unless training began before the range (see `trainedBeforeRange`):
  // then the empty weeks are a break, which is exactly what this insight
  // is for, and every finished week counts except the first, which starts
  // before the range and so holds only some of its sessions.
  final List<WorkoutFrequency> eligibleWeeks;
  if (trainedBeforeRange(
      rangeStart: rangeStart, firstWorkoutAt: firstWorkoutAt)) {
    eligibleWeeks = <WorkoutFrequency>[
      for (final (int i, WorkoutFrequency w) in finishedFrequency.indexed)
        if (i > 0 || !rangeStart!.isAfter(w.weekStart)) w,
    ];
  } else {
    final firstActiveWeek =
        finishedFrequency.indexWhere((week) => week.workoutCount > 0);
    eligibleWeeks = firstActiveWeek == -1
        ? const <WorkoutFrequency>[]
        : finishedFrequency.sublist(firstActiveWeek);
  }
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

  if (finishedVolume.length >= 4) {
    final midpoint = finishedVolume.length ~/ 2;
    final earlier = finishedVolume
        .take(midpoint)
        .fold<double>(0, (sum, row) => sum + row.totalVolumeKg);
    final recent = finishedVolume
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
        subjectId: group.muscleId,
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
