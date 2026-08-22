import 'package:flutter/material.dart';

/// Brand seed and the hand-tuned dark neutrals.
///
/// `ColorScheme.fromSeed` produces a workable palette but its dark surfaces
/// carry a violet cast from the blue seed. The overrides below replace them
/// with true charcoal so that chart lines and the accent read cleanly.
abstract final class AppColors {
  /// Electric blue. Drives the whole generated scheme.
  static const Color seed = Color(0xFF2D6BFF);

  // Dark surface ramp — deliberately neutral.
  static const Color darkSurface = Color(0xFF121416);
  static const Color darkSurfaceContainerLowest = Color(0xFF0C0E10);
  static const Color darkSurfaceContainerLow = Color(0xFF16191C);
  static const Color darkSurfaceContainer = Color(0xFF1B1E22);
  static const Color darkSurfaceContainerHigh = Color(0xFF23272B);
  static const Color darkSurfaceContainerHighest = Color(0xFF2C3035);
  static const Color darkOutlineVariant = Color(0xFF33383D);

  /// Semantic colours for progress indicators. Not derived from the seed,
  /// because "up" and "down" must stay legible in both themes.
  static const Color gain = Color(0xFF3DD68C);
  static const Color loss = Color(0xFFFF6B6B);
  static const Color personalRecord = Color(0xFFFFB020);

  /// Fixed series colours for charts (M5). Ordered for maximum separation
  /// and checked against the dark surface for contrast.
  static const List<Color> chartSeries = <Color>[
    Color(0xFF2D6BFF),
    Color(0xFF3DD68C),
    Color(0xFFFFB020),
    Color(0xFFB47CFF),
    Color(0xFF3ECFDA),
  ];

  /// Fixed-order categorical palette for the muscle-group breakdown,
  /// stepped per theme so bars keep their contrast on both surfaces.
  ///
  /// Order matters — it is what keeps adjacent bars distinguishable under
  /// colour-vision deficiency — so slots are never reassigned or cycled.
  static const List<Color> muscleGroupLight = <Color>[
    Color(0xFF2A78D6),
    Color(0xFFEB6834),
    Color(0xFF1BAF7A),
    Color(0xFFEDA100),
    Color(0xFFE87BA4),
    Color(0xFF008300),
    Color(0xFF4A3AA7),
  ];

  static const List<Color> muscleGroupDark = <Color>[
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
  ];

  /// Reserved slot for the folded-together "Other" bucket.
  static const Color muscleGroupOther = Color(0xFF898781);

  /// Beyond this many groups the smallest fold into "Other" rather than
  /// generating a new hue — an unbounded categorical palette is unreadable.
  static const int muscleGroupSlots = 7;

  /// Palette for the current brightness.
  static List<Color> muscleGroupPalette(Brightness brightness) =>
      brightness == Brightness.dark ? muscleGroupDark : muscleGroupLight;
}
