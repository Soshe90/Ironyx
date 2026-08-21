import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';

part 'timer_settings_controller.freezed.dart';
part 'timer_settings_controller.g.dart';

/// User preferences for timer audio and haptics. Persisted so they survive
/// restart (ADR-1: trivial UI settings live in SharedPreferences).
@freezed
abstract class TimerSettings with _$TimerSettings {
  const factory TimerSettings({
    @Default(true) bool soundEnabled,
    @Default(true) bool hapticsEnabled,
  }) = _TimerSettings;
}

@Riverpod(keepAlive: true)
class TimerSettingsController extends _$TimerSettingsController {
  static const String _soundKey = 'timer_sound_enabled';
  static const String _hapticsKey = 'timer_haptics_enabled';

  @override
  TimerSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return TimerSettings(
      soundEnabled: prefs.getBool(_soundKey) ?? true,
      hapticsEnabled: prefs.getBool(_hapticsKey) ?? true,
    );
  }

  Future<void> setSoundEnabled(bool value) async {
    state = state.copyWith(soundEnabled: value);
    await ref.read(sharedPreferencesProvider).setBool(_soundKey, value);
  }

  Future<void> setHapticsEnabled(bool value) async {
    state = state.copyWith(hapticsEnabled: value);
    await ref.read(sharedPreferencesProvider).setBool(_hapticsKey, value);
  }
}
