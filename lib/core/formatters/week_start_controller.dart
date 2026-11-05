import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers.dart';
import 'week_start.dart';

part 'week_start_controller.g.dart';

/// Persisted first day of the week.
///
/// A display preference like the weight unit: nothing is stored by week,
/// so this only decides how workouts are grouped when they are shown.
///
/// Monday when nothing has been chosen. That is what every week in the app
/// was before this setting existed, so an update regroups nobody's history
/// until they pick a day themselves.
///
/// Kept alive: watched by the dashboard, Progress and the history calendar,
/// so letting it dispose and rebuild would re-read preferences
/// unnecessarily (mirrors `WeightUnitController`).
@Riverpod(keepAlive: true)
class WeekStartController extends _$WeekStartController {
  static const String _prefsKey = 'week_start';

  @override
  WeekStart build() {
    // `get`, not `getString`: that one throws when the stored value is not
    // a string, and this provider is read by the dashboard on launch.
    final Object? stored = ref.watch(sharedPreferencesProvider).get(_prefsKey);
    return _decode(stored is String ? stored : null);
  }

  Future<void> set(WeekStart weekStart) async {
    if (weekStart == state) {
      return;
    }
    state = weekStart;
    await ref.read(sharedPreferencesProvider).setString(
          _prefsKey,
          weekStart.name,
        );
  }

  /// Anything unrecognised reads as Monday: a value written by a newer
  /// build, or a damaged preferences file, must not stop the app opening.
  static WeekStart _decode(String? value) => switch (value) {
        'saturday' => WeekStart.saturday,
        'sunday' => WeekStart.sunday,
        _ => WeekStart.monday,
      };
}
