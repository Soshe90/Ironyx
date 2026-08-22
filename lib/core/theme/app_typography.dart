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

  /// The metric ramp. Fitness numbers carry the hierarchy in this app, so
  /// their sizes are tokens rather than per-screen `fontSize:` overrides.
  ///
  /// Every step is tabular: all four render values that change in place.
  static const double metricSizeSm = 20;
  static const double metricSizeMd = 24;
  static const double metricSizeLg = 32;
  static const double metricSizeXl = 44;

  /// Default size of the timer countdown, when the caller does not scale it
  /// to the available space.
  static const double countdownSize = 64;

  /// Large countdown display. Used by the Timer module (M4).
  ///
  /// [size] lets the active-timer screen scale the digits with its ring
  /// rather than pinning them at a phone-sized 64pt on a tablet.
  static TextStyle countdown(ColorScheme scheme, {double? size}) => TextStyle(
        fontSize: size ?? countdownSize,
        fontWeight: FontWeight.w300,
        height: 1,
        letterSpacing: -1,
        color: scheme.onSurface,
        fontFeatures: _tabular,
      );

  /// Headline number on a dashboard card.
  ///
  /// [size] picks a step off the metric ramp; it defaults to the tile-sized
  /// step so existing call sites keep their weight.
  static TextStyle cardMetric(ColorScheme scheme, {double? size}) => TextStyle(
        fontSize: size ?? 28,
        fontWeight: FontWeight.w600,
        height: 1.1,
        letterSpacing: -0.5,
        color: scheme.onSurface,
        fontFeatures: _tabular,
      );

  /// The small uppercase label that sits above a metric.
  ///
  /// Repeated verbatim in five places before this existed; every copy had
  /// to remember the weight and the letter spacing.
  static TextStyle eyebrow(ThemeData theme, {Color? color}) =>
      theme.textTheme.labelSmall!.copyWith(
        color: color ?? theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      );

  /// Secondary text under a metric or list row.
  static TextStyle caption(ThemeData theme) => theme.textTheme.bodySmall!
      .copyWith(color: theme.colorScheme.onSurfaceVariant);

  static TextTheme apply(TextTheme base) => base.copyWith(
        displayLarge: numeric(base.displayLarge ?? const TextStyle()),
        displayMedium: numeric(base.displayMedium ?? const TextStyle()),
        displaySmall: numeric(base.displaySmall ?? const TextStyle()),
        headlineLarge: numeric(base.headlineLarge ?? const TextStyle()),
      );
}
