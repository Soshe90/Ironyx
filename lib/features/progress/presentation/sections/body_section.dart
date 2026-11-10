/// The Body chapter: its heading and the body measurements.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/tables/body_metrics.dart';
import '../../../../core/database/tables/profiles.dart';
import '../../../../core/formatters/date_formatters.dart';
import '../../../../core/formatters/unit_formatters.dart';
import '../../../../core/formatters/weight_unit_controller.dart';
import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/section_header.dart';
import '../../domain/bmi.dart';
import '../../domain/progress_providers.dart';
import '../widgets/body_metric_widgets.dart';
import '../widgets/progress_charts.dart';

/// The Body chapter's heading. Logging is offered here, as a quiet action,
/// once there is something logged; with nothing logged the empty card below
/// carries the button instead, so it is never shown twice.
///
/// Its own widget so that a new measurement rebuilds this heading, not the
/// page around it.
class BodyMetricsHeader extends ConsumerWidget {
  const BodyMetricsHeader({super.key, required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = context.l10n;
    final bool hasEntries = ref.watch(
      bodyMetricsSeriesProvider(range).select(
        (AsyncValue<List<BodyMetrics>> entries) =>
            entries.value?.isNotEmpty ?? false,
      ),
    );
    return SectionHeader(
      title: l10n.progressBodyMetricsTitle,
      subtitle: l10n.progressBodyMetricsSubtitle,
      actionLabel: hasEntries ? l10n.progressLogMeasurement : null,
      onAction: hasEntries
          ? () => showBodyMetricEditor(
                context,
                ref,
                unit: ref.read(weightUnitControllerProvider),
              )
          : null,
    );
  }
}

/// How many measurements the Progress page lists inline before deferring to
/// the full history page. The page's ListView builds its children eagerly,
/// so this list cannot be unbounded.
const int _inlineMetricEntries = 8;

class BodyMetricsSection extends ConsumerWidget {
  const BodyMetricsSection({super.key, required this.range});

  final ProgressRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BodyMetrics>> async =
        ref.watch(bodyMetricsSeriesProvider(range));
    final AsyncValue<Profile?> profile = ref.watch(progressProfileProvider);
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return async.when(
      loading: () => const ProgressChartLoading(),
      error: (error, _) => ProgressChartError(
        error: error,
        onRetry: () => ref.invalidate(bodyMetricsSeriesProvider(range)),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          // EmptyState's own action, as every other empty card uses, rather
          // than a second button laid out beside it.
          return AppCard(
            child: EmptyState(
              icon: Icons.monitor_weight_outlined,
              title: context.l10n.progressNoMeasurementsTitle,
              message: range == ProgressRange.all
                  ? context.l10n.progressNoMeasurementsMessage
                  : context.l10n.progressNoMeasurementsInRange(range.name),
              actionLabel: context.l10n.progressLogMeasurement,
              onAction: () => showBodyMetricEditor(context, ref, unit: unit),
            ),
          );
        }

        final BodyMetrics latest = entries.first;
        final double? heightCm = profile.value?.heightCm;
        final BmiResult? bmi = heightCm == null
            ? null
            : calculateBmi(weightKg: latest.weightKg, heightCm: heightCm);
        final List<BodyMetrics> shown =
            entries.take(_inlineMetricEntries).toList();
        final int hidden = entries.length - shown.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ProgressChartCard(
              headline:
                  UnitFormatters.weight(latest.weightKg, unit, context.l10n),
              caption: [
                DateFormatters.of(context).relativeDay(latest.date),
                if (latest.bodyFatPercentage != null)
                  context.l10n.progressBodyFatValue(
                    UnitFormatters.oneDecimal(latest.bodyFatPercentage!),
                  ),
                if (bmi != null)
                  context.l10n.progressBmiSummary(
                    UnitFormatters.oneDecimal(bmi.value),
                    switch (bmi.category) {
                      BmiCategory.underweight =>
                        context.l10n.progressBmiUnderweight,
                      BmiCategory.healthy => context.l10n.progressBmiHealthy,
                      BmiCategory.overweight =>
                        context.l10n.progressBmiOverweight,
                      BmiCategory.obesity => context.l10n.progressBmiObesity,
                    },
                  ),
              ].join(' · '),
              child: entries.length >= 2
                  ? DatedLineChart(
                      displayScale: unit.perKilogram,
                      // Stored newest-first; charts read left to right.
                      ordered: <DatedPoint>[
                        for (final BodyMetrics e in entries.reversed)
                          DatedPoint(
                            date: e.date,
                            value: e.weightKg,
                            tooltip: UnitFormatters.weight(
                              e.weightKg,
                              unit,
                              context.l10n,
                            ),
                          ),
                      ],
                      axisLabel: (double kg) => UnitFormatters.weight(
                        kg,
                        unit,
                        context.l10n,
                        withUnit: false,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final BodyMetrics entry in shown)
              BodyMetricTile(entry: entry, unit: unit),
            if (hidden > 0)
              TextButton(
                onPressed: () =>
                    context.pushNamed(Routes.bodyMetricsHistoryName),
                child: Text(
                  context.l10n.progressViewAllMeasurements(hidden),
                ),
              ),
          ],
        );
      },
    );
  }
}
