import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// The grab handle at the top of a bottom sheet.
///
/// Decorative: it is excluded from semantics so a screen reader announces
/// the sheet's heading rather than an unnamed box.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  static const double _width = 40;
  static const double _height = 4;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      child: Center(
        child: Container(
          width: _width,
          height: _height,
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(_height / 2),
          ),
        ),
      ),
    );
  }
}
