import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/theme/app_colors.dart';
import 'package:ironyx/core/theme/app_spacing.dart';
import 'package:ironyx/core/theme/app_theme.dart';

void main() {
  for (final (String name, ThemeData theme) in <(String, ThemeData)>[
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    group('$name theme', () {
      // A component style is read as-is by its widget; without an explicit
      // size it silently renders at the 14dp default. That once made every
      // page title smaller than the section headers beneath it.
      test('page titles are sized as titleLarge (22)', () {
        expect(theme.appBarTheme.titleTextStyle?.fontSize, 22);
      });

      test('navigation labels are sized as labelMedium (12)', () {
        final TextStyle? label = theme.navigationBarTheme.labelTextStyle
            ?.resolve(<WidgetState>{WidgetState.selected});
        expect(label?.fontSize, 12);
        expect(theme.navigationRailTheme.selectedLabelTextStyle?.fontSize, 12);
        expect(
          theme.navigationRailTheme.unselectedLabelTextStyle?.fontSize,
          12,
        );
      });

      test('button labels are sized as labelLarge (14)', () {
        for (final ButtonStyle? style in <ButtonStyle?>[
          theme.filledButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
        ]) {
          expect(style?.textStyle?.resolve(<WidgetState>{})?.fontSize, 14);
        }
      });

      test('page titles align with the content gutter', () {
        expect(theme.appBarTheme.titleSpacing, AppSpacing.lg);
      });
    });
  }

  group('badge text contrast meets WCAG AA (4.5:1)', () {
    for (final (String name, ThemeData theme, Color gain, Color loss, Color pr)
        in <(String, ThemeData, Color, Color, Color)>[
      (
        'light',
        AppTheme.light(),
        AppColors.gainInkLight,
        AppColors.lossInkLight,
        AppColors.personalRecordInkLight,
      ),
      (
        'dark',
        AppTheme.dark(),
        AppColors.gain,
        AppColors.loss,
        AppColors.personalRecord,
      ),
    ]) {
      final ColorScheme s = theme.colorScheme;
      final List<Color> surfaces = <Color>[
        s.surface,
        s.surfaceContainerLowest,
        s.surfaceContainerLow,
        s.surfaceContainer,
        s.surfaceContainerHigh,
      ];
      for (final (String badge, Color ink, Color accent, double alpha)
          in <(String, Color, Color, double)>[
        ('trend up', gain, AppColors.gain, 0.12),
        ('trend down', loss, AppColors.loss, 0.12),
        ('PR', pr, AppColors.personalRecord, 0.16),
      ]) {
        test('$name: $badge on every card surface', () {
          for (final Color surface in surfaces) {
            expect(
              _badgeContrast(ink, accent, alpha, surface),
              greaterThanOrEqualTo(4.5),
              reason: 'on $surface',
            );
          }
        });
      }
    }
  });
}

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Badge text over its own tinted pill (the accent at [alpha] over
/// [surface]), as `TrendBadge` and `PrBadge` draw it.
double _badgeContrast(Color ink, Color accent, double alpha, Color surface) =>
    _contrast(ink, Color.alphaBlend(accent.withValues(alpha: alpha), surface));
