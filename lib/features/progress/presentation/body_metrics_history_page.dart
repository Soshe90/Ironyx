import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/tables/body_metrics.dart';
import '../../../core/formatters/unit_formatters.dart';
import '../../../core/formatters/weight_unit_controller.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/loading_shimmer.dart';
import '../../../core/widgets/page_body.dart';
import '../domain/progress_providers.dart';
import 'widgets/body_metric_widgets.dart';

/// Placeholder rows shown while the query resolves.
const int _skeletonRows = 6;

/// Every logged measurement, newest first.
///
/// Exists so the Progress page can show a short recent list instead of
/// building one card per measurement ever recorded inside its own
/// (non-lazy) `ListView`. This one is a `ListView.builder`, so a user with
/// years of daily weigh-ins builds only what is on screen.
class BodyMetricsHistoryPage extends ConsumerWidget {
  const BodyMetricsHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Deliberately all-time, regardless of the Progress page's range: this
    // is the "show me everything" destination that range selector points at.
    final AsyncValue<List<BodyMetrics>> async =
        ref.watch(bodyMetricsSeriesProvider(ProgressRange.all));
    final WeightUnit unit = ref.watch(weightUnitControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.progressMeasurementsTitle)),
      body: PageBody(
        child: async.when(
          loading: () => ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            children: <Widget>[
              for (int i = 0; i < _skeletonRows; i++)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: LoadingShimmer(height: 64, radius: AppRadius.md),
                ),
            ],
          ),
          error: (error, _) => ErrorView(
            title: context.l10n.progressMeasurementsLoadFailed,
            details: error.toString(),
            onRetry: () =>
                ref.invalidate(bodyMetricsSeriesProvider(ProgressRange.all)),
          ),
          data: (entries) {
            if (entries.isEmpty) {
              return EmptyState(
                icon: Icons.monitor_weight_outlined,
                title: context.l10n.progressNoMeasurementsTitle,
                message: context.l10n.progressNoMeasurementsMessage,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              itemCount: entries.length,
              itemBuilder: (context, index) => BodyMetricTile(
                entry: entries[index],
                unit: unit,
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBodyMetricEditor(context, ref, unit: unit),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.progressLogMeasurement),
      ),
    );
  }
}
