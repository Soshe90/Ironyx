import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ironyx/core/database/app_database.dart';

import '../test/helpers/fake_auth_service.dart';
import 'helpers/e2e_harness.dart';

/// First launch, relaunch, and moving around the shell, on a real device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'a fresh install opens on the welcome screen, seeds the catalogue, and '
      'lands on the dashboard', (tester) async {
    final E2eApp app = await E2eApp.install();
    final Stopwatch coldStart = Stopwatch()..start();
    await app.launch(tester);

    // No accounts in this build, so the only way on is "Get started".
    await pumpUntilFound(tester, find.text('Get started'));
    expect(find.text('Create a free account'), findsNothing);
    await tester.tap(find.text('Get started'));
    await pumpUntilFound(tester, find.text('Start workout'));

    // Both seeders run on first launch, programs after exercises (programs
    // reference them); wait for both rather than assume.
    await tester.runAsync(() async {
      final Stopwatch clock = Stopwatch()..start();
      while (clock.elapsed < const Duration(seconds: 60)) {
        final int exercises =
            (await app.db.select(app.db.exercisesTable).get()).length;
        final int programs =
            (await app.db.select(app.db.programsTable).get()).length;
        if (exercises >= 300 && programs > 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    });
    coldStart.stop();
    final List<ExercisesTableData> exercises =
        await io(tester, () => app.db.select(app.db.exercisesTable).get());
    // ignore: avoid_print
    print('[e2e] first launch to seeded catalogue: '
        '${coldStart.elapsedMilliseconds} ms, ${exercises.length} exercises');
    expect(exercises.length, greaterThanOrEqualTo(300));
    // Built-in programs are seeded alongside.
    final List<ProgramsTableData> programs =
        await io(tester, () => app.db.select(app.db.programsTable).get());
    expect(programs, isNotEmpty);

    // Onboarding is remembered: the next launch skips the welcome screen.
    await app.kill(tester);
    await app.launch(tester);
    await pumpUntilFound(tester, find.text('Start workout'));
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('with accounts available, a guest can still skip sign-up',
      (tester) async {
    final FakeAuthService auth = FakeAuthService();
    addTearDown(auth.dispose);
    final E2eApp app = await E2eApp.install();
    await app.launch(tester, auth: auth);

    await pumpUntilFound(tester, find.text('Continue without an account'));
    expect(find.text('Create a free account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);

    await tester.tap(find.text('Continue without an account'));
    await pumpUntilFound(tester, find.text('Start workout'));
    expect(auth.currentUser, isNull);
    expect(auth.accounts, isEmpty);
  });

  testWidgets('every destination opens, and re-tapping a tab is harmless',
      (tester) async {
    final E2eApp app =
        await E2eApp.install(prefs: {'onboarding_complete': true});
    await app.launch(tester);
    await pumpUntilFound(tester, find.byType(NavigationBar));

    // Twice round, so each tab is also re-selected while already current,
    // which pops that branch to its root.
    for (int lap = 0; lap < 2; lap++) {
      for (final String label in <String>[
        'Workouts',
        'Library',
        'Timer',
        'Progress',
        'Home',
      ]) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull, reason: 'opening $label');
      }
    }
    expect(find.text('Start workout'), findsOneWidget);
  });
}
