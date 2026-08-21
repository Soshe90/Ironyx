import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers.dart';

part 'theme_mode_controller.g.dart';

/// Persisted light/dark/system preference.
///
/// Kept alive: the theme is read on every frame of every route, so letting
/// it dispose and rebuild would re-read preferences unnecessarily.
@Riverpod(keepAlive: true)
class ThemeModeController extends _$ThemeModeController {
  static const String _prefsKey = 'theme_mode';

  @override
  ThemeMode build() {
    final String? stored = ref.watch(sharedPreferencesProvider).getString(
          _prefsKey,
        );
    return _decode(stored);
  }

  Future<void> set(ThemeMode mode) async {
    if (mode == state) {
      return;
    }
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(
          _prefsKey,
          _encode(mode),
        );
  }

  /// Convenience for the settings toggle: cycles system -> light -> dark.
  Future<void> cycle() async {
    final ThemeMode next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await set(next);
  }

  static ThemeMode _decode(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _encode(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
