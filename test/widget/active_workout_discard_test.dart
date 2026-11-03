import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/theme/app_spacing.dart';
import 'package:ironyx/features/tracker/domain/active_workout_notifier.dart';
import 'package:ironyx/features/tracker/presentation/active_workout_page.dart';

import '../helpers/pump_app.dart';

/// Discarding a workout through the real screens.
///
/// Regression for "I discarded it three times and it is still in
/// progress": the discard was deferred, so the workout stayed visible for
/// the undo window, opening it cancelled the discard, and the Undo
/// snackbar never went away (Flutter now persists snackbars that have an
/// action) — tapping that stale Undo started a fresh empty workout.
void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.forTesting());

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    await database.close();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  /// Starts a workout from Home and discards it through the menu.
  Future<String> startAndDiscard(WidgetTester tester) async {
    await pumpApp(
      tester,
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    final String id = containerOf(tester).read(activeWorkoutProvider)!.id;

    await tester.tap(find.byTooltip('Workout options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard workout'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    return id;
  }

  testWidgets('the workout is gone the moment the discard is confirmed',
      (tester) async {
    await startAndDiscard(tester);

    expect(find.byType(ActiveWorkoutPage), findsNothing);
    expect(containerOf(tester).read(activeWorkoutProvider), isNull);
    expect(find.text('Workout in progress'), findsNothing);
    expect(find.text('Start workout'), findsOneWidget);
    expect(find.text('Workout discarded'), findsOneWidget);

    await disposeApp(tester);
  });

  testWidgets('the Undo snackbar closes with the undo window', (tester) async {
    await startAndDiscard(tester);

    await tester.pump(AppDuration.undoWindow + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Workout discarded'), findsNothing,
        reason: 'a lingering Undo is what restarted discarded workouts');
    expect(find.text('Undo'), findsNothing);
    expect(containerOf(tester).read(activeWorkoutProvider), isNull);

    await disposeApp(tester);
  });

  testWidgets('Undo inside the window restores the workout and reopens it',
      (tester) async {
    final String id = await startAndDiscard(tester);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.byType(ActiveWorkoutPage), findsOneWidget);
    expect(containerOf(tester).read(activeWorkoutProvider)!.id, id,
        reason: 'the same workout comes back, not a new empty one');

    await disposeApp(tester);
  });

  testWidgets('starting again during the window starts a new workout',
      (tester) async {
    final String id = await startAndDiscard(tester);

    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    final String fresh = containerOf(tester).read(activeWorkoutProvider)!.id;
    expect(fresh, isNot(id),
        reason: 'opening the workout screen must not cancel a discard');

    // The old snackbar's Undo cannot overwrite the new workout either.
    final ActiveWorkoutNotifier notifier =
        containerOf(tester).read(activeWorkoutProvider.notifier);
    expect(await notifier.undoDiscard(), isFalse);
    expect(containerOf(tester).read(activeWorkoutProvider)!.id, fresh);

    await disposeApp(tester);
  });
}
