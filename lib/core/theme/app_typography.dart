import 'package:flutter/material.dart';

/// Typography helpers.
///
/// The app ships with the platform default family. If a custom family is
/// added later, register it here rather than at call sites.
///
/// ADR cross-cutting rule: anything rendering live-changing digits — the
/// timer, weights, volume totals — must use tabular figures, otherwise the
/// layout jitters as digit widths change while counting.
abstract final class AppTypography {
  static const List<FontFeature> _tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// Applies tabular figures to an existing style.
  static TextStyle numeric(TextStyle style) =>
      style.copyWith(fontFeatures: _tabular);

  /// Large countdown display. Used by the Timer module (M4).
  static TextStyle countdown(ColorScheme scheme) => TextStyle(
        fontSize: 64,
        fontWeight: FontWeight.w300,
        height: 1,
        letterSpacing: -1,
        color: scheme.onSurface,
        fontFeatures: _tabular,
      );

  /// Headline number on a dashboard card.
  static TextStyle cardMetric(ColorScheme scheme) => TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        height: 1.1,
        color: scheme.onSurface,
        fontFeatures: _tabular,
      );

  static TextTheme apply(TextTheme base) => base.copyWith(
        displayLarge: numeric(base.displayLarge ?? const TextStyle()),
        displayMedium: numeric(base.displayMedium ?? const TextStyle()),
        displaySmall: numeric(base.displaySmall ?? const TextStyle()),
        headlineLarge: numeric(base.headlineLarge ?? const TextStyle()),
      );
}
