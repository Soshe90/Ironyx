import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/error_reporting.dart';
import 'core/providers.dart';
import 'core/widgets/error_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();
  _registerAssetLicenses();

  // Resolved before the first frame so that the theme does not flash from
  // light to dark on launch.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  await _initSupabase();

  // Create the provider scope and trigger the seeder
  final container = ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const IronyxApp(),
  );

  runApp(container);
}

/// Makes sure an uncaught error is reported and shown, instead of vanishing
/// in release (nothing was previously wired up: no crash reporter, no
/// override of the default red error screen) or crashing the whole engine.
///
/// `FlutterError.onError` and `ErrorWidget.builder` between them cover
/// widget build/layout/paint errors. `PlatformDispatcher.instance.onError`
/// additionally catches everything outside the widget tree — a `Future`
/// that fails with no `catch`, a stream listener that throws, platform
/// channel callbacks — which would otherwise reach the zone's default
/// handler and, on some platforms, terminate the process.
void _installErrorHandlers() {
  final FlutterExceptionHandler? previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    reportError(details.exception, details.stack, context: 'FlutterError');
    previousOnError?.call(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    reportError(error, stack, context: 'PlatformDispatcher');
    // Handled: false would additionally fall through to the platform's
    // own unhandled-error behaviour, which on some embedders means
    // terminating the isolate. This app runs on, in whatever state it can
    // — ADR-6's "degrade, never throw" applied to the whole process rather
    // than one capability.
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) {
    reportError(details.exception, details.stack, context: 'ErrorWidget');
    // Wrapped in `Directionality` + `Material` rather than relying on
    // ancestors: this replaces whatever widget failed to build, which can be
    // above `MaterialApp` itself (a bad `theme:`/`locale:` computation, say),
    // so neither is guaranteed to exist yet. `title` is passed explicitly
    // rather than left to `ErrorView`'s default for the same reason — that
    // default reads `context.l10n`, which throws if `Localizations` isn't
    // mounted, and the widget standing in for "everything else already
    // failed" cannot itself have a failure mode.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        child: ErrorView(
          title: kDebugMode
              ? '${details.exception}'
              : 'Something went wrong. Please restart the app.',
        ),
      ),
    );
  };
}

/// Adds the exercise catalogue's licence to Settings -> About -> Open-source
/// licenses (`showLicensePage`), alongside the package licences Flutter
/// already collects there automatically. See `ASSETS-LICENSE.md` — this is
/// the one credit not owed automatically by a package dependency, since the
/// catalogue is bundled data, not a package.
void _registerAssetLicenses() {
  LicenseRegistry.addLicense(() {
    return Stream<LicenseEntry>.value(
      const LicenseEntryWithLineBreaks(
        <String>['free-exercise-db'],
        'Exercise names, instructions, and photos are from free-exercise-db '
        '(https://github.com/yuhonas/free-exercise-db), dedicated to the '
        'public domain under The Unlicense (https://unlicense.org/). No '
        'attribution is required by that licence; this entry is here '
        'anyway. See ASSETS-LICENSE.md for the full provenance record.',
      ),
    );
  });
}

/// Brings up the Supabase client, but only when this build has credentials.
///
/// Accounts are optional (see `docs/ADR.md`, ADR-8), so a build without
/// `--dart-define=SUPABASE_URL=...` must launch and behave exactly as it did
/// before accounts existed. A failure here is also non-fatal: `initialize`
/// restores a cached session from local storage and can attempt a token
/// refresh, and a dead network on launch must not stop the app from opening
/// to a fully usable offline workout tracker.
Future<void> _initSupabase() async {
  if (!SupabaseConfig.isConfigured) {
    if (kDebugMode) {
      debugPrint('[auth] No Supabase credentials in this build; accounts off.');
    }
    return;
  }
  // Host only — never the key. Confirms the --dart-define actually landed,
  // which is the first thing to rule out when every request "can't reach the
  // server": a bare project ref, or a URL missing its scheme, fails exactly
  // that way.
  if (kDebugMode) debugPrint('[auth] Supabase URL: ${SupabaseConfig.url}');
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // `anonKey` is the deprecated spelling of the same value; Supabase
      // renamed it to "publishable key" without changing what you paste in.
      publishableKey: SupabaseConfig.anonKey,
    );
  } on Object catch (error, stackTrace) {
    if (kDebugMode) {
      debugPrint('Supabase initialization failed; continuing signed out.');
    }
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
  }
}
