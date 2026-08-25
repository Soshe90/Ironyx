enum BmiCategory { underweight, healthy, overweight, obesity }

class BmiResult {
  const BmiResult({required this.value, required this.category});

  final double value;
  final BmiCategory category;
}

/// Calculates BMI from kilograms and centimetres. BMI is intentionally a
/// derived display metric: height and weight remain the source data, so it
/// never becomes stale or needs a migration.
BmiResult? calculateBmi({required double weightKg, required double heightCm}) {
  if (!weightKg.isFinite ||
      !heightCm.isFinite ||
      weightKg <= 0 ||
      heightCm <= 0) {
    return null;
  }
  final heightM = heightCm / 100;
  final value = weightKg / (heightM * heightM);
  if (!value.isFinite) return null;
  return BmiResult(value: value, category: bmiCategory(value));
}

BmiCategory bmiCategory(double value) => switch (value) {
      < 18.5 => BmiCategory.underweight,
      < 25 => BmiCategory.healthy,
      < 30 => BmiCategory.overweight,
      _ => BmiCategory.obesity,
    };
