import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers.dart';

part 'onboarding_controller.g.dart';

/// Whether the welcome screen has already been dismissed on this device.
///
/// Kept alive and synchronous: `createRouter` reads it once to pick the
/// launch route, and a future that resolved a frame later would flash the
/// dashboard before the welcome screen replaced it.
///
/// Deliberately keyed to the install, not to the account. Signing out is not
/// a reason to re-introduce the app to someone who has been using it for
/// months, and — per ADR-8 — uninstalling clears preferences along with
/// everything else, which is exactly when the intro is worth showing again.
@Riverpod(keepAlive: true)
class OnboardingController extends _$OnboardingController {
  static const String _prefsKey = 'onboarding_complete';

  @override
  bool build() =>
      ref.watch(sharedPreferencesProvider).getBool(_prefsKey) ?? false;

  /// Records that the user has made their choice on the welcome screen.
  ///
  /// Called for all three exits — account, sign-in, guest — because the
  /// screen has served its purpose either way. Someone who taps "Create
  /// account" and then backs out of the form has still seen the intro, and
  /// showing it to them again on the next launch would read as a bug.
  Future<void> complete() async {
    if (state) {
      return;
    }
    state = true;
    await ref.read(sharedPreferencesProvider).setBool(_prefsKey, true);
  }
}
