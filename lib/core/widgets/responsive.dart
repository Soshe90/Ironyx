import 'package:flutter/widgets.dart';

/// Layout breakpoints.
///
/// Verified at 360dp (phone), 768dp (tablet) and 1440dp (desktop web).
enum Breakpoint {
  compact(0),
  medium(768),
  expanded(1200);

  const Breakpoint(this.minWidth);

  final double minWidth;

  static Breakpoint of(double width) {
    if (width >= Breakpoint.expanded.minWidth) {
      return Breakpoint.expanded;
    }
    if (width >= Breakpoint.medium.minWidth) {
      return Breakpoint.medium;
    }
    return Breakpoint.compact;
  }
}

extension BreakpointContext on BuildContext {
  Breakpoint get breakpoint => Breakpoint.of(MediaQuery.sizeOf(this).width);

  bool isAtLeast(Breakpoint b) => MediaQuery.sizeOf(this).width >= b.minWidth;

  /// Column count for the dashboard grid.
  int get gridColumns => switch (breakpoint) {
        Breakpoint.compact => 1,
        Breakpoint.medium => 2,
        Breakpoint.expanded => 3,
      };

  /// Caps content width so text does not run edge to edge on desktop.
  double get contentMaxWidth => switch (breakpoint) {
        Breakpoint.compact => double.infinity,
        Breakpoint.medium => 900,
        Breakpoint.expanded => 1100,
      };
}
