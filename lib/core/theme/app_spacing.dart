/// Spacing, radius and duration constants.
///
/// ADR cross-cutting rule: no magic numbers in feature code. Every gap,
/// padding, radius and animation duration comes from here.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Minimum interactive target. Material accessibility floor.
  static const double minTapTarget = 48;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

abstract final class AppDuration {
  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration normal = Duration(milliseconds: 260);
  static const Duration slow = Duration(milliseconds: 400);

  /// Debounce for text inputs that write into shared state (ADR-5).
  static const Duration inputDebounce = Duration(milliseconds: 300);

  /// Window during which a discarded workout can be undone.
  static const Duration undoWindow = Duration(seconds: 5);
}
