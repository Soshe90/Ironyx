import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'page_body.dart';

/// A fixed bar holding a screen's primary commit action.
///
/// Used by the active-workout and workout-edit screens so that finishing or
/// saving is always one tap away, rather than sitting at the bottom of a
/// scroll list that grows with every exercise added.
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: PageBody(child: child),
        ),
      ),
    );
  }
}
