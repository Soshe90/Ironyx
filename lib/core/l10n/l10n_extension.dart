import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

export '../../l10n/app_localizations.dart' show AppLocalizations;

/// `context.l10n.actionSave` instead of `AppLocalizations.of(context)!...`.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// The active language tag, for the `intl` formatters that take one.
  ///
  /// `DateFormat` and friends live outside the widget tree and so cannot
  /// reach `AppLocalizations` themselves; the call sites pass this down.
  String get localeName => Localizations.localeOf(this).toLanguageTag();
}
