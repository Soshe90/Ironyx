import 'dart:ui';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers.dart';

part 'locale_controller.g.dart';

/// The languages this build ships translations for.
///
/// Kept in the same order the settings picker renders them, with the
/// device-follows option first.
const List<Locale> kSupportedLocales = <Locale>[
  Locale('en'),
  Locale('ar'),
];

/// Persisted language preference.
///
/// A `null` state means "follow the device", which is the default and what
/// [Locale] resolution in `MaterialApp` does when handed a null locale.
///
/// Kept alive for the same reason as the theme: `MaterialApp` reads it on
/// every frame of every route.
@Riverpod(keepAlive: true)
class LocaleController extends _$LocaleController {
  static const String _prefsKey = 'app_locale';

  /// Stored for "follow the device". A bare absent key would be
  /// indistinguishable from a first launch, which is fine today, but writing
  /// the choice explicitly keeps a future default change from silently
  /// re-deciding for people who already picked.
  static const String _systemValue = 'system';

  @override
  Locale? build() {
    final String? stored = ref.watch(sharedPreferencesProvider).getString(
          _prefsKey,
        );
    return _decode(stored);
  }

  Future<void> set(Locale? locale) async {
    if (locale == state) {
      return;
    }
    state = locale;
    await ref.read(sharedPreferencesProvider).setString(
          _prefsKey,
          locale?.languageCode ?? _systemValue,
        );
  }

  /// Resolves an unknown or removed language tag back to "follow the device"
  /// rather than trusting whatever string is in preferences: a build that
  /// drops a translation must not strand its users on a locale with no
  /// strings.
  static Locale? _decode(String? value) {
    if (value == null || value == _systemValue) {
      return null;
    }
    for (final Locale locale in kSupportedLocales) {
      if (locale.languageCode == value) {
        return locale;
      }
    }
    return null;
  }
}
