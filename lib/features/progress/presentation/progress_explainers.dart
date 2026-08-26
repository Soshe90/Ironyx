import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/widgets/metric_explainer.dart';

/// The Progress page's glossary, one [MetricExplainer] per jargon-named
/// section.
///
/// Kept together in one file rather than inline at each `SectionHeader` for
/// two reasons: the page is already long enough without eight blocks of copy
/// in the middle of it, and having the explanations side by side is what
/// keeps them consistent in voice and depth. They are functions of
/// [AppLocalizations] rather than constants because every string is
/// translated, and translation happens at display time.
abstract final class ProgressExplainers {
  static MetricExplainer strengthChange(AppLocalizations l10n) =>
      MetricExplainer(
        title: l10n.progressStrengthChangeTitle,
        icon: Icons.trending_up_rounded,
        summary: l10n.explainerStrengthChangeSummary,
        points: <String>[
          l10n.explainerStrengthChangePoint1,
          l10n.explainerStrengthChangePoint2,
        ],
        caveat: l10n.explainerStrengthChangeCaveat,
      );

  static MetricExplainer oneRm(AppLocalizations l10n) => MetricExplainer(
        title: l10n.progressEstimatedOneRmTitle,
        icon: Icons.fitness_center_rounded,
        summary: l10n.explainerOneRmSummary,
        formula: l10n.explainerOneRmFormula,
        example: l10n.explainerOneRmExample,
        points: <String>[
          l10n.explainerOneRmPoint1,
          l10n.explainerOneRmPoint2,
          l10n.explainerOneRmPoint3,
        ],
        caveat: l10n.explainerOneRmCaveat,
      );

  static MetricExplainer relativeStrength(AppLocalizations l10n) =>
      MetricExplainer(
        title: l10n.progressRelativeStrengthTitle,
        icon: Icons.monitor_weight_outlined,
        summary: l10n.explainerRelativeStrengthSummary,
        formula: l10n.explainerRelativeStrengthFormula,
        example: l10n.explainerRelativeStrengthExample,
        points: <String>[
          l10n.explainerRelativeStrengthPoint1,
          l10n.explainerRelativeStrengthPoint2,
        ],
        caveat: l10n.explainerRelativeStrengthCaveat,
      );

  static MetricExplainer volume(AppLocalizations l10n) => MetricExplainer(
        title: l10n.progressWeeklyVolumeTitle,
        icon: Icons.stacked_bar_chart_rounded,
        summary: l10n.explainerVolumeSummary,
        formula: l10n.explainerVolumeFormula,
        example: l10n.explainerVolumeExample,
        points: <String>[
          l10n.explainerVolumePoint1,
          l10n.explainerVolumePoint2,
          l10n.explainerVolumePoint3,
        ],
      );

  static MetricExplainer consistency(AppLocalizations l10n) => MetricExplainer(
        title: l10n.progressConsistencyTitle,
        icon: Icons.local_fire_department_rounded,
        summary: l10n.explainerConsistencySummary,
        points: <String>[
          l10n.explainerConsistencyPoint1,
          l10n.explainerConsistencyPoint2,
        ],
        caveat: l10n.explainerConsistencyCaveat,
      );

  static MetricExplainer rpe(AppLocalizations l10n) => MetricExplainer(
        title: l10n.progressEffortRecoveryTitle,
        icon: Icons.speed_rounded,
        summary: l10n.explainerRpeSummary,
        formula: l10n.explainerRpeFormula,
        points: <String>[
          l10n.explainerRpePoint1,
          l10n.explainerRpePoint2,
        ],
        caveat: l10n.explainerRpeCaveat,
      );

  static MetricExplainer balance(AppLocalizations l10n) => MetricExplainer(
        title: l10n.progressTrainingBalanceTitle,
        icon: Icons.balance_rounded,
        summary: l10n.explainerBalanceSummary,
        formula: l10n.explainerBalanceFormula,
        example: l10n.explainerBalanceExample,
        points: <String>[
          l10n.explainerBalancePoint1,
          l10n.explainerBalancePoint2,
        ],
        caveat: l10n.explainerBalanceCaveat,
      );

  static MetricExplainer repRange(AppLocalizations l10n) => MetricExplainer(
        title: l10n.progressRepRangeDistributionTitle,
        icon: Icons.donut_small_rounded,
        summary: l10n.explainerRepRangeSummary,
        formula: l10n.explainerRepRangeFormula,
        points: <String>[
          l10n.explainerRepRangePoint1,
          l10n.explainerRepRangePoint2,
          l10n.explainerRepRangePoint3,
        ],
        caveat: l10n.explainerRepRangeCaveat,
      );
}
