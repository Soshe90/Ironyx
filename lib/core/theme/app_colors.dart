import 'package:flutter/material.dart';

/// Brand seed and the hand-tuned dark neutrals.
///
/// `ColorScheme.fromSeed` produces a workable palette but its dark surfaces
/// carry a tint from the seed. The overrides below replace them with true
/// charcoal so that chart lines and the accent read cleanly.
abstract final class AppColors {
  /// Brand teal, the same hue as the launcher icon and `web/manifest.json`
  /// (`theme_color`). Drives the whole generated scheme.
  static const Color seed = Color(0xFF38D6C0);

  /// Focused workout surface, intentionally distinct from browsing surfaces.
  static const Color workoutHero = Color(0xFF092F32);
  // Deep enough that the vivid accent button and its label keep 4.5:1
  // across the whole gradient.
  static const Color workoutHeroEnd = Color(0xFF0E5753);
  static const Color workoutHeroAccent = darkAccent;
  static const Color workoutHeroForeground = Color(0xFFFFFFFF);
  static const Color workoutHeroCaption = Color(0xFFD4E7E2);

  // Light surface ramp — quiet neutrals keep teal reserved for emphasis.
  static const Color lightSurface = Color(0xFFF5F7F6);
  static const Color lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLow = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainer = Color(0xFFEEF3F1);
  static const Color lightSurfaceContainerHigh = Color(0xFFE7EFEC);
  static const Color lightSurfaceContainerHighest = Color(0xFFDCE6E2);
  static const Color lightOutlineVariant = Color(0xFFD6DFDB);

  // Dark surface ramp — the app's primary look. Near-black ink with a faint
  // cool cast, stepped just enough that a card reads against the page
  // without needing a heavy border.
  static const Color darkSurface = Color(0xFF0E1113);
  static const Color darkSurfaceContainerLowest = Color(0xFF090B0D);
  static const Color darkSurfaceContainerLow = Color(0xFF161A1D);
  static const Color darkSurfaceContainer = Color(0xFF1B2024);
  // Held just dark enough that the red trend-down badge keeps 4.5:1 on it.
  static const Color darkSurfaceContainerHigh = Color(0xFF20262A);
  static const Color darkSurfaceContainerHighest = Color(0xFF2C3338);
  static const Color darkOutlineVariant = Color(0xFF252C31);

  /// The dark theme's single vivid accent, replacing the seed's softer
  /// tone. It carries every primary action, the selected tab and the Work
  /// phase, so it is kept for those and nothing decorative.
  static const Color darkAccent = Color(0xFF3CF0C8);

  /// Text and icons on [darkAccent]: the accent is light, so ink on it.
  static const Color onDarkAccent = Color(0xFF00241D);

  /// Semantic colours for progress indicators. Not derived from the seed,
  /// because "up" and "down" must stay legible in both themes.
  static const Color gain = Color(0xFF3DD68C);
  static const Color loss = Color(0xFFFF6B6B);
  static const Color personalRecord = Color(0xFFFFB020);

  /// Text and icon colours for the three accents above on light surfaces.
  ///
  /// The accents are bright enough to read on the dark theme's charcoal but
  /// only ~1.5:1 as text on their own pale tint in light mode. These darker
  /// inks of the same hue reach at least 4.5:1 (WCAG AA) on that tint over
  /// every light surface; the tinted pill itself still uses the accent.
  static const Color gainInkLight = Color(0xFF0B6B3A);
  static const Color lossInkLight = Color(0xFFB3261E);
  static const Color personalRecordInkLight = Color(0xFF8A5300);

  /// Running-timer phase hues, so Rest, Prepare and Cooldown can be told
  /// apart from Work (the brand primary) from across the room. The phase
  /// name is always shown too, so colour is never the only signal.
  ///
  /// Each light value reaches at least 4.5:1 as text on [lightSurface], and
  /// each dark value on [darkSurface]. Prepare is its own token rather than
  /// [personalRecord], even though the hue matches, so the PR accent keeps
  /// a single meaning.
  static const Color phaseRestLight = Color(0xFF1F63C7);
  static const Color phaseRestDark = Color(0xFF7AB0FF);
  static const Color phasePrepareLight = Color(0xFF8A5300);
  static const Color phasePrepareDark = Color(0xFFFFB020);
  static const Color phaseCooldownLight = Color(0xFF5B4BC4);
  static const Color phaseCooldownDark = Color(0xFFB47CFF);

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
