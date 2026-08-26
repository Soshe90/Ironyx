import 'package:fittrack/features/profile/domain/bmi_advisory.dart';
import 'package:fittrack/l10n/app_localizations.dart';
import 'package:fittrack/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The advisory wording is localized now; the bands themselves are not.
  final AppLocalizations l10n = AppLocalizationsEn();

  group('bmi', () {
    test('computes the standard kg/m^2 value', () {
      // 94 kg at 172 cm — the numbers from the reference screenshot.
      expect(
        BmiAdvisory.bmi(weightKg: 94, heightCm: 172),
        closeTo(31.77, 0.01),
      );
    });

    test('returns null rather than throwing on missing or absurd input', () {
      expect(BmiAdvisory.bmi(weightKg: null, heightCm: 172), isNull);
      expect(BmiAdvisory.bmi(weightKg: 80, heightCm: null), isNull);
      expect(BmiAdvisory.bmi(weightKg: 0, heightCm: 172), isNull);
      // Division by zero would otherwise yield infinity and render as a
      // nonsense advisory.
      expect(BmiAdvisory.bmi(weightKg: 80, heightCm: 0), isNull);
      expect(BmiAdvisory.bmi(weightKg: -5, heightCm: 172), isNull);
    });
  });

  group('band', () {
    test('splits on the WHO cut-offs', () {
      // 18.5 and 25 are the boundaries; each belongs to the higher band.
      expect(BmiAdvisory.band(weightKg: 50, heightCm: 175),
          BmiBand.underweight); // 16.3
      expect(BmiAdvisory.band(weightKg: 57, heightCm: 175.5),
          BmiBand.healthy); // 18.5
      expect(BmiAdvisory.band(weightKg: 70, heightCm: 175),
          BmiBand.healthy); // 22.9
      expect(BmiAdvisory.band(weightKg: 80, heightCm: 175),
          BmiBand.overweight); // 26.1
      expect(BmiAdvisory.band(weightKg: 94, heightCm: 172), BmiBand.obese);
    });
  });

  group('message', () {
    test('stays silent for a healthy reading and for incomplete input', () {
      expect(
          BmiAdvisory.message(weightKg: 70, heightCm: 175, l10n: l10n), isNull);
      expect(BmiAdvisory.message(weightKg: null, heightCm: 175, l10n: l10n),
          isNull);
      expect(BmiAdvisory.message(weightKg: 70, heightCm: null, l10n: l10n),
          isNull);
    });

    test('asks the user to check their input rather than judging them', () {
      final String? high =
          BmiAdvisory.message(weightKg: 94, heightCm: 172, l10n: l10n);
      expect(high, contains('overweight'));
      expect(high, contains('check'));

      final String? low =
          BmiAdvisory.message(weightKg: 45, heightCm: 175, l10n: l10n);
      expect(low, contains('underweight'));
      expect(low, contains('check'));
    });
  });
}
