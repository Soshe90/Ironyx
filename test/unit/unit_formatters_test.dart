import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';
import 'package:ironyx/l10n/app_localizations.dart';

void main() {
  final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
  final AppLocalizations ar = lookupAppLocalizations(const Locale('ar'));

  // Left-to-right isolate ... pop directional isolate.
  const String lri = '\u2066';
  const String pdi = '\u2069';
  const String nbsp = '\u00A0';

  group('right-to-left locales', () {
    test('a measurement is one left-to-right run, so Arabic never shows "kg 0"',
        () {
      expect(UnitFormatters.volume(0, WeightUnit.kg, ar), '${lri}0 kg$pdi');
      expect(
          UnitFormatters.weight(85.5, WeightUnit.lb, ar), '${lri}188.5 lb$pdi');
      expect(UnitFormatters.estimate(101.4, WeightUnit.kg, ar),
          '${lri}101 kg$pdi');
      expect(
          UnitFormatters.weightRate(-2, WeightUnit.kg, ar), '$lri-2.0 kg$pdi');
    });

    test('a bare number needs no isolate', () {
      expect(
        UnitFormatters.weight(100, WeightUnit.kg, ar, withUnit: false),
        '100',
      );
    });

    test('English output is unchanged, byte for byte', () {
      expect(UnitFormatters.volume(0, WeightUnit.kg, en), '0 kg');
      expect(UnitFormatters.volume(0, WeightUnit.kg, en), isNot(contains(lri)));
    });
  });

  group('durationShort in Arabic', () {
    test('uses Arabic abbreviations, not Latin m/h', () {
      expect(
          UnitFormatters.durationShort(const Duration(minutes: 1), ar), '1 د');
      expect(
        UnitFormatters.durationShort(const Duration(hours: 1, minutes: 12), ar),
        '1 س 12 د',
      );
      expect(UnitFormatters.durationShort(const Duration(hours: 2), ar), '2 س');
      expect(UnitFormatters.durationShort(Duration.zero, ar), '0 د');
    });
  });

  group('setLine', () {
    test('joins weight and reps with non-breaking spaces', () {
      expect(
        UnitFormatters.setLine(60, 8, WeightUnit.kg, en),
        '60${nbsp}kg$nbsp×${nbsp}8',
      );
      expect(
        UnitFormatters.setLine(100, 5, WeightUnit.lb, en),
        '220.46${nbsp}lb$nbsp×${nbsp}5',
      );
    });

    test('is a single isolate in Arabic, so it cannot render as "60 8 × kg"',
        () {
      expect(
        UnitFormatters.setLine(60, 8, WeightUnit.kg, ar),
        '${lri}60${nbsp}kg$nbsp×${nbsp}8$pdi',
      );
    });
  });

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
        expect(UnitFormatters.weight(100, WeightUnit.kg, en), '100 kg');
        expect(UnitFormatters.weight(85.5, WeightUnit.kg, en), '85.5 kg');
        expect(UnitFormatters.weight(0, WeightUnit.kg, en), '0 kg');
      });

      test('lb formatting with unit', () {
        expect(UnitFormatters.weight(100, WeightUnit.lb, en), '220.46 lb');
        expect(UnitFormatters.weight(85.5, WeightUnit.lb, en), '188.5 lb');
      });

      test('formatting without unit', () {
        expect(
          UnitFormatters.weight(100, WeightUnit.kg, en, withUnit: false),
          '100',
        );
        expect(
          UnitFormatters.weight(100, WeightUnit.lb, en, withUnit: false),
          '220.46',
        );
      });

      test('volume formatting', () {
        // 100kg * 10 reps = 1000 kg volume
        expect(UnitFormatters.volume(1000, WeightUnit.kg, en), '1,000 kg');
        expect(UnitFormatters.volume(1000, WeightUnit.lb, en), '2,205 lb');
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
        expect(UnitFormatters.durationShort(const Duration(minutes: 48), en),
            '48m');
        expect(
          UnitFormatters.durationShort(
              const Duration(hours: 1, minutes: 12), en),
          '1h 12m',
        );
        expect(
            UnitFormatters.durationShort(const Duration(hours: 2), en), '2h');
        expect(
          UnitFormatters.durationShort(
              const Duration(hours: 1, minutes: 0), en),
          '1h',
        );
      });
    });

    group('weight rate', () {
      test('shows one decimal, never two and never rounded to zero', () {
        expect(UnitFormatters.weightRate(11.84, WeightUnit.kg, en), '11.8 kg');
        expect(UnitFormatters.weightRate(0.4, WeightUnit.kg, en), '0.4 kg');
        expect(UnitFormatters.weightRate(-2, WeightUnit.kg, en), '-2.0 kg');
        expect(UnitFormatters.weightRate(10, WeightUnit.lb, en), '22.0 lb');
      });
    });
  });
}
