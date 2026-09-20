import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';

void main() {
  group('UnitFormatters', () {
    group('weight conversion', () {
      test('kg to lb conversion is accurate', () {
        expect(
          UnitFormatters.fromKg(100, WeightUnit.lb),
          closeTo(220.46, 0.01),
        );
        expect(UnitFormatters.fromKg(1, WeightUnit.lb), closeTo(2.20, 0.01));
        expect(UnitFormatters.fromKg(0, WeightUnit.lb), 0);
      });

      test('lb to kg conversion is accurate', () {
        expect(UnitFormatters.toKg(220.462, WeightUnit.lb), closeTo(100, 0.01));
        expect(UnitFormatters.toKg(2.205, WeightUnit.lb), closeTo(1, 0.01));
        expect(UnitFormatters.toKg(0, WeightUnit.lb), 0);
      });

      test('round-trip kg -> lb -> kg preserves value', () {
        const originalKg = 85.5;
        final lb = UnitFormatters.fromKg(originalKg, WeightUnit.lb);
        final backToKg = UnitFormatters.toKg(lb, WeightUnit.lb);
        expect(backToKg, closeTo(originalKg, 0.001));
      });

      test('round-trip lb -> kg -> lb preserves value', () {
        const originalLb = 185.5;
        final kg = UnitFormatters.toKg(originalLb, WeightUnit.lb);
        final backToLb = UnitFormatters.fromKg(kg, WeightUnit.lb);
        expect(backToLb, closeTo(originalLb, 0.001));
      });

      test('kg formatting with unit', () {
        expect(UnitFormatters.weight(100, WeightUnit.kg), '100 kg');
        expect(UnitFormatters.weight(85.5, WeightUnit.kg), '85.5 kg');
        expect(UnitFormatters.weight(0, WeightUnit.kg), '0 kg');
      });

      test('lb formatting with unit', () {
        expect(UnitFormatters.weight(100, WeightUnit.lb), '220.46 lb');
        expect(UnitFormatters.weight(85.5, WeightUnit.lb), '188.5 lb');
      });

      test('formatting without unit', () {
        expect(
          UnitFormatters.weight(100, WeightUnit.kg, withUnit: false),
          '100',
        );
        expect(
          UnitFormatters.weight(100, WeightUnit.lb, withUnit: false),
          '220.46',
        );
      });

      test('volume formatting', () {
        // 100kg * 10 reps = 1000 kg volume
        expect(UnitFormatters.volume(1000, WeightUnit.kg), '1,000 kg');
        expect(UnitFormatters.volume(1000, WeightUnit.lb), '2,205 lb');
      });
    });

    group('duration formatting', () {
      test('duration formats hours, minutes, seconds', () {
        expect(
          UnitFormatters.duration(
              const Duration(hours: 1, minutes: 5, seconds: 3)),
          '1:05:03',
        );
        expect(
          UnitFormatters.duration(const Duration(minutes: 5, seconds: 3)),
          '05:03',
        );
        expect(UnitFormatters.duration(const Duration(seconds: 45)), '00:45');
        expect(UnitFormatters.duration(const Duration(hours: 2)), '2:00:00');
      });

      test('durationRoundedUp keeps live countdowns ahead of zero', () {
        expect(
          UnitFormatters.durationRoundedUp(
            const Duration(seconds: 3, milliseconds: 900),
          ),
          '00:04',
        );
        expect(
          UnitFormatters.secondsRoundedUp(
            const Duration(seconds: 1, milliseconds: 1),
          ),
          2,
        );
        expect(
          UnitFormatters.durationRoundedUp(const Duration(milliseconds: 1)),
          '00:01',
        );
        expect(
          UnitFormatters.durationRoundedUp(const Duration(milliseconds: -1)),
          '00:00',
        );
      });

      test('durationShort formats compact', () {
        expect(
            UnitFormatters.durationShort(const Duration(minutes: 48)), '48m');
        expect(
          UnitFormatters.durationShort(const Duration(hours: 1, minutes: 12)),
          '1h 12m',
        );
        expect(UnitFormatters.durationShort(const Duration(hours: 2)), '2h');
        expect(
          UnitFormatters.durationShort(const Duration(hours: 1, minutes: 0)),
          '1h',
        );
      });
    });
  });
}
