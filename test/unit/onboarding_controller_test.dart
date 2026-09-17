import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/features/onboarding/domain/onboarding_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> containerWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final SharedPreferences instance = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(instance)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('a fresh install has not seen onboarding', () async {
    final container = await containerWith(const <String, Object>{});

    expect(container.read(onboardingControllerProvider), isFalse);
  });

  test('a stored flag is read back on the next launch', () async {
    final container = await containerWith(
      const <String, Object>{'onboarding_complete': true},
    );

    expect(container.read(onboardingControllerProvider), isTrue);
  });

  test('complete() flips the state and persists it', () async {
    final container = await containerWith(const <String, Object>{});

    await container.read(onboardingControllerProvider.notifier).complete();

    expect(container.read(onboardingControllerProvider), isTrue);
    // Survives a relaunch: a new container reading the same store.
    final SharedPreferences reread = await SharedPreferences.getInstance();
    expect(reread.getBool('onboarding_complete'), isTrue);
  });

  test('complete() is idempotent', () async {
    final container = await containerWith(const <String, Object>{});
    final notifier = container.read(onboardingControllerProvider.notifier);

    await notifier.complete();
    await notifier.complete();

    expect(container.read(onboardingControllerProvider), isTrue);
  });
}
