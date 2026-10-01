import 'package:flutter/material.dart';

/// Typography helpers.
///
/// The app bundles Barlow for its interface and Barlow Condensed for metric
/// numbers (`pubspec.yaml`, licence in `assets/fonts/OFL.txt`), so it looks
/// the same on every phone. Families are named here, never at call sites.
///
/// ADR cross-cutting rule: anything rendering live-changing digits — the
/// timer, weights, volume totals — must use tabular figures, otherwise the
/// layout jitters as digit widths change while counting. Both families
/// ship a `tnum` feature, which [numeric] switches on.
abstract final class AppTypography {
  /// Interface face, set once on `ThemeData.fontFamily`.
  static const String fontFamily = 'Barlow';

  /// Metric numbers: condensed and bold, so a headline figure is large
  /// without being wide, which is the athletic look the app is going for.
  static const String numericFamily = 'BarlowCondensed';

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

  /// A number typed into a form field (timer builder). Larger than body text
  /// so the value reads at a glance, below the metric ramp so a field never
  /// outweighs the numbers it produces.
  static const double fieldValueSize = 18;

  /// Default size of the timer countdown, when the caller does not scale it
  /// to the available space.
  static const double countdownSize = 64;

  /// Large countdown display. Used by the Timer module (M4).
  ///
  /// [size] lets the active-timer screen scale the digits with its ring
  /// rather than pinning them at a phone-sized 64pt on a tablet.
  static TextStyle countdown(ColorScheme scheme, {double? size}) => TextStyle(
        fontFamily: numericFamily,
        fontSize: size ?? countdownSize,
        fontWeight: FontWeight.w600,
        height: 1,
        letterSpacing: 0,
        color: scheme.onSurface,
        fontFeatures: _tabular,
      );

  /// Headline number on a dashboard card.
  ///
  /// [size] picks a step off the metric ramp; it defaults to the tile-sized
  /// step so existing call sites keep their weight.
  static TextStyle cardMetric(ColorScheme scheme, {double? size}) => TextStyle(
        fontFamily: numericFamily,
        fontSize: size ?? 28,
        fontWeight: FontWeight.w700,
        height: 1.1,
        letterSpacing: 0,
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
        fontWeight: FontWeight.w700,
        // Wider tracking than body text: the eyebrow is set in capitals,
        // and tight capitals read as a smudge at this size.
        letterSpacing: 0.8,
      );

  /// Secondary text under a metric or list row.
  static TextStyle caption(ThemeData theme) => theme.textTheme.bodySmall!
      .copyWith(color: theme.colorScheme.onSurfaceVariant);

  static TextTheme apply(TextTheme base) => base.copyWith(
        displayLarge: numeric(
          (base.displayLarge ?? const TextStyle()).copyWith(
            fontFamily: numericFamily,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
          ),
        ),
        displayMedium: numeric(
          (base.displayMedium ?? const TextStyle()).copyWith(
            fontFamily: numericFamily,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.8,
          ),
        ),
        displaySmall: numeric(
          (base.displaySmall ?? const TextStyle()).copyWith(
            fontFamily: numericFamily,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        headlineLarge: numeric(
          (base.headlineLarge ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        headlineMedium: numeric(
          (base.headlineMedium ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        headlineSmall: (base.headlineSmall ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleLarge: (base.titleLarge ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.1,
        ),
        titleMedium: (base.titleMedium ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        titleSmall: (base.titleSmall ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        bodyLarge: (base.bodyLarge ?? const TextStyle()).copyWith(
          letterSpacing: 0,
        ),
        bodyMedium: (base.bodyMedium ?? const TextStyle()).copyWith(
          letterSpacing: 0,
        ),
        bodySmall: (base.bodySmall ?? const TextStyle()).copyWith(
          letterSpacing: 0,
        ),
        labelLarge: (base.labelLarge ?? const TextStyle()).copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        labelMedium: (base.labelMedium ?? const TextStyle()).copyWith(
          letterSpacing: 0,
        ),
        labelSmall: (base.labelSmall ?? const TextStyle()).copyWith(
          letterSpacing: 0,
        ),
      );
}
