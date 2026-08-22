import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/supabase_config.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolved before the first frame so that the theme does not flash from
  // light to dark on launch.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  await _initSupabase();

  // Create the provider scope and trigger the seeder
  final container = ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const FitTrackApp(),
  );

  runApp(container);
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
    debugPrint('[auth] No Supabase credentials in this build; accounts off.');
    return;
  }
  // Host only — never the key. Confirms the --dart-define actually landed,
  // which is the first thing to rule out when every request "can't reach the
  // server": a bare project ref, or a URL missing its scheme, fails exactly
  // that way.
  debugPrint('[auth] Supabase URL: ${SupabaseConfig.url}');
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // `anonKey` is the deprecated spelling of the same value; Supabase
      // renamed it to "publishable key" without changing what you paste in.
      publishableKey: SupabaseConfig.anonKey,
    );
  } on Object catch (error, stackTrace) {
    debugPrint('Supabase initialization failed; continuing signed out.');
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stackTrace),
    );
  }
}
