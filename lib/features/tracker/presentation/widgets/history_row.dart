/// One row of the Workouts history: date tile, exercises as the title,
/// time and duration, and the volume (or sets) on the trailing edge.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/tables/workouts.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/services/clock.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/pr_badge.dart';

/// Width of a history row's date tile; the row dividers are inset by it so
/// they start under the text, not under the tile.
const double historyDateTileWidth = 52;

/// How many exercise names a row title spells out before "+N".
const int _titleExerciseLimit = 2;

class WorkoutHistoryTile extends ConsumerWidget {
  const WorkoutHistoryTile({
    super.key,
    required this.workout,
    required this.isPersonalRecord,
    required this.exerciseNames,
    this.setCount,
    this.onOpen,
  });

  final Workout workout;
  final bool isPersonalRecord;

  /// Completed sets, shown instead of the volume when the workout has none
  /// (bodyweight or timed sets), where "0 kg" read as nothing done. Null
  /// while the counts load: the volume shows until then.
  final int? setCount;

  /// What a tap does; opening the workout's page when null. The day sheet
  /// passes its own, to close with the choice.
  final VoidCallback? onOpen;

  /// Localized, in logged order. Empty for a workout with no exercises.
  final List<String> exerciseNames;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final AppLocalizations l10n = context.l10n;
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);
    final DateFormatters dates = DateFormatters.of(context);
    final String time = dates.time(workout.startedAt);
    final String duration = workout.durationSeconds == null
        ? l10n.trackerNoDuration
        : UnitFormatters.durationShort(
            Duration(seconds: workout.durationSeconds!),
            context.l10n,
          );
    // Named by what was trained; the start time is secondary. The screen
    // reader hears every exercise; the visible title is fitted by
    // [_HistoryTitle].
    final String? title =
        exerciseNames.isEmpty ? null : exerciseNames.join(l10n.listSeparator);
    // A workout with no load is measured in sets; it cannot hold a record
    // either, since a record needs weight.
    final bool bySets = workout.totalVolumeKg <= 0 && setCount != null;
    final String volumeText = bySets
        ? l10n.trackerSetCount(setCount!)
        : UnitFormatters.volume(workout.totalVolumeKg, unit, context.l10n);
    final String summary = bySets
        ? l10n.trackerWorkoutSemanticSets(
            dates.full(workout.startedAt),
            volumeText,
          )
        : isPersonalRecord
            ? l10n.trackerWorkoutSemanticPr(
                dates.full(workout.startedAt),
                volumeText,
              )
            : l10n.trackerWorkoutSemantic(
                dates.full(workout.startedAt),
                volumeText,
              );
    // Watched, not read from the clock: the list outlives the day it was
    // built on, and yesterday's row must stop saying "today".
    final DateTime today = ref.watch(todayProvider);
    final bool isToday = workout.startedAt.year == today.year &&
        workout.startedAt.month == today.month &&
        workout.startedAt.day == today.day;

    return Semantics(
      label: title == null ? summary : '$title. $summary',
      button: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onOpen ??
              () => context.pushNamed(
                    Routes.workoutDetailName,
                    pathParameters: {'id': workout.id},
                  ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Row(
              children: [
                _DateTile(date: workout.startedAt, isToday: isToday),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HistoryTitle(names: exerciseNames, fallback: time),
                      const SizedBox(height: AppSpacing.xxs),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title == null ? duration : '$time · $duration',
                              style: AppTypography.caption(theme),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isPersonalRecord) ...[
                            const SizedBox(width: AppSpacing.sm),
                            const PrBadge(),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  volumeText,
                  style: AppTypography.cardMetric(
                    scheme,
                    size: AppTypography.metricSizeSm,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "+4": how many exercises a history row's title leaves out.
class _MoreExercisesPill extends StatelessWidget {
  const _MoreExercisesPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: _padding,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label, style: styleOf(theme)),
    );
  }

  static const double _padding = AppSpacing.sm;

  static TextStyle styleOf(ThemeData theme) => AppTypography.numeric(
        theme.textTheme.labelMedium!.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      );

  /// The pill's horizontal padding, for callers measuring its width.
  static double get horizontalPadding => _padding * 2;
}

/// A history row's title: up to two exercise names, then a "+N" pill for
/// the rest. Measured before it is laid out, so when two names do not fit
/// beside the pill the second is dropped and counted, rather than being
/// cut mid-word ("Back Squat, Overhead P...").
class _HistoryTitle extends StatelessWidget {
  const _HistoryTitle({required this.names, required this.fallback});

  /// Localized, in logged order.
  final List<String> names;

  /// Shown when the workout has no exercises.
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle style = theme.textTheme.titleSmall!;
    if (names.isEmpty) {
      return Text(
        fallback,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    final AppLocalizations l10n = context.l10n;
    final TextScaler scaler = MediaQuery.textScalerOf(context);
    final TextDirection direction = Directionality.of(context);

    double widthOf(String text, TextStyle textStyle) {
      final TextPainter painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final double width = painter.width;
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        double pillWidth(int extra) => extra == 0
            ? 0
            : widthOf(
                  l10n.trackerMoreExercises(extra),
                  _MoreExercisesPill.styleOf(theme),
                ) +
                _MoreExercisesPill.horizontalPadding +
                AppSpacing.xs;

        int shown = names.length < _titleExerciseLimit
            ? names.length
            : _titleExerciseLimit;
        while (shown > 1 &&
            widthOf(names.take(shown).join(l10n.listSeparator), style) +
                    pillWidth(names.length - shown) >
                constraints.maxWidth) {
          shown--;
        }
        final int extra = names.length - shown;
        // At the largest text sizes the volume beside this title leaves it
        // a sliver, narrower than the pill alone. The pill is dropped then
        // rather than drawn off the row; the row's spoken label still
        // names every exercise.
        final bool pillFits =
            extra > 0 && pillWidth(extra) <= constraints.maxWidth;

        return Row(
          children: [
            Flexible(
              child: Text(
                names.take(shown).join(l10n.listSeparator),
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pillFits) ...[
              const SizedBox(width: AppSpacing.xs),
              _MoreExercisesPill(label: l10n.trackerMoreExercises(extra)),
            ],
          ],
        );
      },
    );
  }
}

/// Day number over a short weekday: the row's visual anchor, and what used
/// to be a heading above it. Today's tile takes the accent.
class _DateTile extends StatelessWidget {
  const _DateTile({required this.date, required this.isToday});

  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final DateFormatters dates = DateFormatters.of(context);
    final Color ink = isToday ? scheme.primary : scheme.onSurface;

    // The row's semantics label already carries the full date.
    return ExcludeSemantics(
      child: Container(
        width: historyDateTileWidth,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isToday
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              dates.dayOfMonth(date),
              style: AppTypography.cardMetric(
                scheme,
                size: AppTypography.metricSizeMd,
              ).copyWith(color: ink, height: 1),
            ),
            const SizedBox(height: AppSpacing.xxs),
            // Arabic has no short weekday names, so the label scales down
            // rather than overflowing the tile.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                dates.weekdayShort(date).toUpperCase(),
                maxLines: 1,
                style: AppTypography.eyebrow(
                  theme,
                  color: isToday ? scheme.primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
