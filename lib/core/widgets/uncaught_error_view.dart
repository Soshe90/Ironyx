import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../../l10n/app_localizations.dart';
import '../error_reporting.dart';
import 'error_view.dart';

/// What `ErrorWidget.builder` puts in place of a widget that failed to
/// build.
///
/// Wrapped in `Directionality` + `Material` rather than relying on
/// ancestors: this replaces whatever widget failed, which can be above
/// `MaterialApp` itself (a bad `theme:`/`locale:` computation, say), so
/// neither is guaranteed to exist. Nothing here may depend on an ancestor
/// being present: the widget standing in for "everything else already
/// failed" cannot itself have a failure mode.
///
/// A debug build shows the exception and [debugErrorSummary]. A release
/// build shows one translated sentence and nothing about the error, which
/// can carry personal data (see `reportError`).
class UncaughtErrorView extends StatelessWidget {
  const UncaughtErrorView({
    required this.details,
    this.firstInBurst,
    this.debug = kDebugMode,
    super.key,
  });

  final FlutterErrorDetails details;

  /// The first error of the burst [details] belongs to, if it is a
  /// different one. See `ErrorBurst`.
  final String? firstInBurst;

  /// Whether to show the developer's view. A parameter so that tests can
  /// cover what a release build shows.
  final bool debug;

  @override
  Widget build(BuildContext context) {
    if (debug) {
      final String summary =
          debugErrorSummary(details, firstInBurst: firstInBurst);
      // Left to right whatever the app's language: exception text and stack
      // frames are English and code. Scrollable because this can stand in
      // for a widget far smaller than a dozen lines of text, and a layout
      // overflow here would be one more error on top of the one shown.
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          child: Center(
            child: SingleChildScrollView(
              child: ErrorView(
                title: '${details.exception}',
                details: summary.isEmpty ? null : summary,
              ),
            ),
          ),
        ),
      );
    }

    final AppLocalizations l10n = _localizationsFor(context);
    return Directionality(
      textDirection: intl.Bidi.isRtlLanguage(l10n.localeName)
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Material(child: ErrorView(title: l10n.errorUncaught)),
    );
  }

  /// The app's strings without needing `Localizations` above this widget.
  ///
  /// Uses the app's own locale when the failure is below `MaterialApp`,
  /// which is the usual case and honours the language chosen in Settings.
  /// Above it, falls back to the device's language, then to English.
  static AppLocalizations _localizationsFor(BuildContext context) {
    final Locale locale = Localizations.maybeLocaleOf(context) ??
        WidgetsBinding.instance.platformDispatcher.locale;
    try {
      return lookupAppLocalizations(locale);
    } on Object catch (_) {
      // A device language the app has no translation for.
      return lookupAppLocalizations(const Locale('en'));
    }
  }
}
