import '../../../core/l10n/l10n_extension.dart';

/// Body-mass-index bands, used only to sanity-check what the user typed.
enum BmiBand { underweight, healthy, overweight, obese }

/// A plausibility check on the height and weight entered in Personal
/// Details.
///
/// The point is catching a slipped decimal or a lb/kg mix-up — someone
/// entering 172 kg instead of 172 cm — not telling anybody what to weigh.
/// BMI is a poor measure of an individual (it reads a muscular lifter as
/// overweight, which for this audience is common), so the wording asks the
/// user to *check* their input and the caller must never block on it.
abstract final class BmiAdvisory {
  /// BMI, or null when either input is missing or non-physical.
  static double? bmi({required double? weightKg, required double? heightCm}) {
    if (weightKg == null || heightCm == null) return null;
    if (weightKg <= 0 || heightCm <= 0) return null;
    final double metres = heightCm / 100;
    return weightKg / (metres * metres);
  }

  static BmiBand? band({required double? weightKg, required double? heightCm}) {
    final double? value = bmi(weightKg: weightKg, heightCm: heightCm);
    if (value == null) return null;
    // WHO cut-offs.
    if (value < 18.5) return BmiBand.underweight;
    if (value < 25) return BmiBand.healthy;
    if (value < 30) return BmiBand.overweight;
    return BmiBand.obese;
  }

  /// The advisory line, or null when the numbers look unremarkable.
  ///
  /// Null for [BmiBand.healthy] on purpose: an advisory that appears on
  /// every screen is one nobody reads.
  static String? message({
    required double? weightKg,
    required double? heightCm,
    required AppLocalizations l10n,
  }) {
    return switch (band(weightKg: weightKg, heightCm: heightCm)) {
      null || BmiBand.healthy => null,
      BmiBand.underweight => l10n.profileBmiUnderweight,
      BmiBand.overweight || BmiBand.obese => l10n.profileBmiOverweight,
    };
  }
}
