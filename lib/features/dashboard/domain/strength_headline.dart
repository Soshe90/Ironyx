import '../../../core/database/daos/workout_dao.dart';
import '../../progress/domain/progress_insights.dart';

/// What Home's "Est. 1RM" tile shows: one lift's best estimate and which
/// way it is going.
class StrengthHeadline {
  const StrengthHeadline({
    required this.exerciseId,
    required this.exerciseName,
    required this.bestKg,
    required this.trend,
  });

  final String exerciseId;
  final String exerciseName;

  /// Best estimated 1RM: over the last three months, or over all time when
  /// no lift was trained in them.
  final double bestKg;

  /// Null when there is nothing fair to compare with: see
  /// [pickStrengthHeadline].
  final OneRMTrend? trend;
}

/// Picks the lift for Home's tile and judges its trend, the way Progress
/// does for the same lift.
///
/// The tile used to show the most-logged lift's *last* session against the
/// session before it. A light day or a deload then read as a lower 1RM
/// with a red arrow (0.5 kg was enough), and Progress, which shows the
/// best in its range, gave the same lift a different number. Now:
///
/// * **The lift** is the most-trained one ([lifts], most sessions first,
///   the list Progress's lift chart opens on) that was trained in the last
///   three months ([recent]). Failing that, the most-trained lift, with its
///   all-time best from [allTime] and no arrow: someone back from a break
///   still sees their lift, but nothing claims a trend over the break.
/// * **The figure** is the best estimate in those three months, as on
///   Progress's default range.
/// * **The trend** compares it with the best before them. Under
///   [minInsightStrengthChange] (2.5%, about one rep on a set of 5 to 10)
///   it is flat: Epley moves that much between sessions of the same
///   strength. No arrow without an earlier best, or when the only thing to
///   compare with is the lift's first session in the window, where people
///   start light: Progress words that case as "since your first session",
///   which a tile has no room for.
StrengthHeadline? pickStrengthHeadline({
  required List<LoggedExercise> lifts,
  required List<StrengthChange> recent,
  required List<StrengthChange> allTime,
}) {
  StrengthChange? rowFor(List<StrengthChange> rows, String id) {
    for (final StrengthChange row in rows) {
      if (row.exerciseId == id) return row;
    }
    return null;
  }

  for (final LoggedExercise lift in lifts) {
    final StrengthChange? row = rowFor(recent, lift.exerciseId);
    if (row != null) {
      return StrengthHeadline(
        exerciseId: row.exerciseId,
        exerciseName: row.exerciseName,
        bestKg: row.currentBestKg,
        trend: _trendOf(row),
      );
    }
  }
  if (lifts.isEmpty) return null;
  final StrengthChange? row = rowFor(allTime, lifts.first.exerciseId);
  if (row == null) return null;
  return StrengthHeadline(
    exerciseId: row.exerciseId,
    exerciseName: row.exerciseName,
    bestKg: row.currentBestKg,
    trend: null,
  );
}

OneRMTrend? _trendOf(StrengthChange row) {
  final double? change = row.change;
  if (change == null || row.comparedWithFirstSession) return null;
  if (change.abs() < minInsightStrengthChange) return OneRMTrend.flat;
  return change > 0 ? OneRMTrend.up : OneRMTrend.down;
}
