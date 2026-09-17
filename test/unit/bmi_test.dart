import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/features/progress/domain/bmi.dart';

void main() {
  test('calculates BMI and category from metric source values', () {
    final result = calculateBmi(weightKg: 81, heightCm: 180);
    expect(result, isNotNull);
    expect(result!.value, closeTo(25, .01));
    // An enum, not a display string: the wording is localized at the point
    // of display (see `progressBmiOverweight`), so the domain layer only
    // carries the band.
    expect(result.category, BmiCategory.overweight);
  });

  test('returns null for missing or invalid measurements', () {
    expect(calculateBmi(weightKg: 80, heightCm: 0), isNull);
    expect(calculateBmi(weightKg: -1, heightCm: 180), isNull);
    expect(calculateBmi(weightKg: double.nan, heightCm: 180), isNull);
  });
}
