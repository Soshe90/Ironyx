import 'dart:ui';


import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../l10n/app_localizations.dart';
import 'locale_controller.dart';

part 'l10n_provider.g.dart';

/// [AppLocalizations] for code that runs outside the widget tree.
///
/// Most strings should come from `context.l10n`. This exists for the few
/// that cannot: scheduled notification text, above all, which is written
/// while the timer is running and read from the system tray long after the
/// widget that started it is gone.
///
/// Kept alive so a locale change rebuilds it once rather than on each read.
@Riverpod(keepAlive: true)
Future<AppLocalizations> appLocalizations(Ref ref) {
  final Locale? preferred = ref.watch(localeControllerProvider);
  return AppLocalizations.delegate.load(preferred ?? _deviceLocale());
}

/// The device's preferred language, narrowed to one this app translates.
///
/// Mirrors what `MaterialApp` resolves to when handed a null `locale`, so a
/// notification cannot arrive in a different language from the screen that
/// scheduled it. Falls back to English when the device asks for something
/// unsupported, which is what `basicLocaleListResolution` does too.
Locale _deviceLocale() {
  for (final Locale candidate in PlatformDispatcher.instance.locales) {
    for (final Locale supported in kSupportedLocales) {
      if (candidate.languageCode == supported.languageCode) {
        return supported;
      }
    }
  }
  return kSupportedLocales.first;
}
