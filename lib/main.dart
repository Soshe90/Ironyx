import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolved before the first frame so that the theme does not flash from
  // light to dark on launch.
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // Create the provider scope and trigger the seeder
  final container = ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const FitTrackApp(),
  );

  runApp(container);
}
