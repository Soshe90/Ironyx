import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Standard surface for grouped content.
///
/// Tappable variants get an ink ripple and a semantics label so the card
/// reads correctly to a screen reader as a single button.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.semanticLabel,
    this.gradient,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final BorderRadius radius = BorderRadius.circular(AppRadius.xl);

    final Widget content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: radius,
      ),
      child: Padding(padding: padding, child: child),
    );

    final Widget card = Material(
      color: gradient == null ? scheme.surfaceContainerLow : Colors.transparent,
      elevation: gradient == null ? 1 : 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );

    if (semanticLabel == null) {
      return card;
    }
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: card,
    );
  }
}
