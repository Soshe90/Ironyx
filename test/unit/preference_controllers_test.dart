import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';
import 'package:ironyx/core/formatters/weight_unit_controller.dart';
import 'package:ironyx/core/l10n/locale_controller.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/theme/theme_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three persisted display preferences: language, theme and weight unit.
///
/// Each is read synchronously before the first frame, so a bad stored value
/// must fall back to a default rather than throw: a throw here is a crash on
/// every launch, with no screen from which to fix it.
void main() {
  Future<ProviderContainer> containerWith(Map<String, Object> stored) async {
    SharedPreferences.setMockInitialValues(stored);
    final ProviderContainer container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<ProviderContainer> relaunch() async {
    final ProviderContainer container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('LocaleController', () {
    test('follows the device when nothing is stored', () async {
      final ProviderContainer c = await containerWith({});
      expect(c.read(localeControllerProvider), isNull);
    });

    test('restores each supported language', () async {
      for (final Locale locale in kSupportedLocales) {
        final ProviderContainer c =
            await containerWith({'app_locale': locale.languageCode});
        expect(c.read(localeControllerProvider), locale);
      }
    });

    for (final String stored in <String>[
      'system',
      'fr',
      '',
      'EN',
      'en_US',
      'ar-SA',
    ]) {
      test('"$stored" falls back to following the device', () async {
        final ProviderContainer c = await containerWith({'app_locale': stored});
        expect(c.read(localeControllerProvider), isNull);
      });
    }

    test('a chosen language survives a relaunch', () async {
      final ProviderContainer c = await containerWith({});
      await c.read(localeControllerProvider.notifier).set(const Locale('ar'));
      expect(c.read(localeControllerProvider), const Locale('ar'));
      c.dispose();

      expect((await relaunch()).read(localeControllerProvider),
          const Locale('ar'));
    });

    test('going back to "follow the device" is stored explicitly', () async {
      final ProviderContainer c = await containerWith({'app_locale': 'ar'});
      await c.read(localeControllerProvider.notifier).set(null);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_locale'), 'system');
      expect(c.read(localeControllerProvider), isNull);
    });

    test('setting the current value does not write', () async {
      final ProviderContainer c = await containerWith({});
      await c.read(localeControllerProvider.notifier).set(null);

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('app_locale'), isFalse);
    });
  });

  group('ThemeModeController', () {
    // Dark is the app's primary look (2026-10-01 restyle), so a fresh
    // install opens dark; an explicit "system" choice is still honoured.
    test('defaults to the dark theme', () async {
      final ProviderContainer c = await containerWith({});
      expect(c.read(themeModeControllerProvider), ThemeMode.dark);
    });

    test('keeps an explicit system choice', () async {
      final ProviderContainer c = await containerWith({'theme_mode': 'system'});
      expect(c.read(themeModeControllerProvider), ThemeMode.system);
    });

    test('restores light and dark', () async {
      expect(
        (await containerWith({'theme_mode': 'light'}))
            .read(themeModeControllerProvider),
        ThemeMode.light,
      );
      expect(
        (await containerWith({'theme_mode': 'dark'}))
            .read(themeModeControllerProvider),
        ThemeMode.dark,
      );
    });

    test('an unknown stored value falls back to the default', () async {
      for (final String stored in <String>['DARK', 'amoled', '', ' dark']) {
        final ProviderContainer c = await containerWith({'theme_mode': stored});
        expect(c.read(themeModeControllerProvider), ThemeMode.dark,
            reason: 'stored "$stored"');
      }
    });

    test('cycle goes system, light, dark, and back to system', () async {
      final ProviderContainer c = await containerWith({'theme_mode': 'system'});
      final ThemeModeController notifier =
          c.read(themeModeControllerProvider.notifier);
      final List<ThemeMode> seen = <ThemeMode>[];
      for (int i = 0; i < 4; i++) {
        await notifier.cycle();
        seen.add(c.read(themeModeControllerProvider));
      }
      expect(seen, <ThemeMode>[
        ThemeMode.light,
        ThemeMode.dark,
        ThemeMode.system,
        ThemeMode.light,
      ]);
    });

    test('the choice survives a relaunch', () async {
      final ProviderContainer c = await containerWith({});
      // Light, because dark is the default and setting it stores nothing.
      await c.read(themeModeControllerProvider.notifier).set(ThemeMode.light);
      c.dispose();

      expect(
        (await relaunch()).read(themeModeControllerProvider),
        ThemeMode.light,
      );
    });
  });

  group('WeightUnitController', () {
    test('defaults to kilograms', () async {
      final ProviderContainer c = await containerWith({});
      expect(c.read(weightUnitControllerProvider), WeightUnit.kg);
    });

    test('restores pounds', () async {
      final ProviderContainer c = await containerWith({'weight_unit': 'lb'});
      expect(c.read(weightUnitControllerProvider), WeightUnit.lb);
    });

    test('an unknown stored value falls back to kilograms', () async {
      for (final String stored in <String>['LB', 'lbs', 'stone', '']) {
        final ProviderContainer c =
            await containerWith({'weight_unit': stored});
        expect(c.read(weightUnitControllerProvider), WeightUnit.kg,
            reason: 'stored "$stored"');
      }
    });

    test('the choice survives a relaunch', () async {
      final ProviderContainer c = await containerWith({});
      await c.read(weightUnitControllerProvider.notifier).set(WeightUnit.lb);
      c.dispose();

      expect(
        (await relaunch()).read(weightUnitControllerProvider),
        WeightUnit.lb,
      );
    });
  });
}
