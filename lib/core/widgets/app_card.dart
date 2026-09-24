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
    final bool light = scheme.brightness == Brightness.light;
    final BorderRadius radius = BorderRadius.circular(AppRadius.lg);

    final Widget content = DecoratedBox(
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: radius,
      ),
      child: Padding(padding: padding, child: child),
    );

    // One separation cue per theme, not three. Light: a white card lifted
    // off the tinted background by a soft shadow — an outline on top of
    // that was the main source of visual noise. Dark: shadows don't read on
    // charcoal and the fill step is small, so a hairline does the work.
    final Widget card = Material(
      color: gradient != null
          ? Colors.transparent
          : light
              ? scheme.surfaceContainerLowest
              : scheme.surfaceContainerLow,
      elevation: gradient == null && light ? 1 : 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: light
            ? BorderSide.none
            : BorderSide(
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
