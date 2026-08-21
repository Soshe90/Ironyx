import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/equipment_dao.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/database/daos/muscle_dao.dart';
import 'package:fittrack/core/database/database_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

void main() {
  group('LibraryPage', () {
    late AppDatabase database;

    // The app boots with a real exercise seeder that would replace this test's
    // four seeded exercises with the full asset catalogue. A pre-seeded version
    // makes the seeder short-circuit so the test owns the exact dataset.
    const Map<String, Object> seededPrefs = <String, Object>{
      'exercise_seed_version': 999999,
    };

    // Tall enough that every exercise card in the one-column grid is built —
    // GridView.builder is lazy, so off-screen items are not in the tree.
    const Size surface = Size(400, 2400);

    setUp(() async {
      database = AppDatabase.forTesting();
      final exerciseDao = ExerciseDao(database);
      final muscleDao = MuscleDao(database);
      final equipmentDao = EquipmentDao(database);

      await muscleDao.upsertAll([
        MusclesTableCompanion.insert(
          id: 'chest',
          name: 'chest',
          displayName: 'Chest',
        ),
        MusclesTableCompanion.insert(
          id: 'back',
          name: 'back',
          displayName: 'Back',
        ),
        MusclesTableCompanion.insert(
          id: 'legs',
          name: 'legs',
          displayName: 'Legs',
        ),
      ]);
      await equipmentDao.upsertAll([
        EquipmentTableCompanion.insert(id: 'barbell', name: 'Barbell'),
        EquipmentTableCompanion.insert(id: 'bodyweight', name: 'Bodyweight'),
      ]);

      Future<void> seed({
        required String id,
        required String name,
        required String muscleId,
        required String equipmentId,
        required String instructions,
      }) async {
        await exerciseDao.upsertExercises([
          ExercisesTableCompanion.insert(
            id: id,
            slug: id,
            name: name,
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'horizontalPush',
            seedVersion: 1,
          ),
        ]);
        await exerciseDao.replaceMuscleLinks(id, [
          ExerciseMusclesTableCompanion.insert(
            id: '${id}_m',
            exerciseId: id,
            muscleId: muscleId,
            role: 'primary',
          ),
        ]);
        await exerciseDao.replaceEquipmentLinks(id, [
          ExerciseEquipmentTableCompanion.insert(
            id: '${id}_eq',
            exerciseId: id,
            equipmentId: equipmentId,
          ),
        ]);
        await exerciseDao.replaceInstructions(id, [
          ExerciseInstructionsTableCompanion.insert(
            id: '${id}_step',
            exerciseId: id,
            stepNumber: 1,
            instruction: instructions,
          ),
        ]);
      }

      await seed(
        id: 'bench_1',
        name: 'Barbell Bench Press',
        muscleId: 'chest',
        equipmentId: 'barbell',
        instructions: 'Lie on bench, press bar.',
      );
      await seed(
        id: 'squat_1',
        name: 'Back Squat',
        muscleId: 'legs',
        equipmentId: 'barbell',
        instructions: 'Squat with bar on back.',
      );
      await seed(
        id: 'pushup_1',
        name: 'Push-Up',
        muscleId: 'chest',
        equipmentId: 'bodyweight',
        instructions: 'Push up from floor.',
      );
      await seed(
        id: 'pullup_1',
        name: 'Pull-Up',
        muscleId: 'back',
        equipmentId: 'bodyweight',
        instructions: 'Pull chin over bar.',
      );
    });

    // Drift's reactive stream cache keeps a zero-duration timer alive after a
    // stream is unsubscribed. Replacing the tree disposes the provider scope
    // (cancelling the stream) and the following pump fires that deferred
    // timer, so the test ends with no pending timers.
    Future<void> disposeApp(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await database.close();
    }

    Future<void> pumpLibrary(WidgetTester tester) => pumpApp(
          tester,
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          initialLocation: '/library',
          prefs: seededPrefs,
          surfaceSize: surface,
        );

    testWidgets('displays exercise list', (tester) async {
      await pumpLibrary(tester);

      expect(find.text('Exercise Library'), findsOneWidget);
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.text('Back Squat'), findsOneWidget);
      expect(find.text('Push-Up'), findsOneWidget);
      expect(find.text('Pull-Up'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('search filters exercises', (tester) async {
      await pumpLibrary(tester);

      // Search for "bench"
      await tester.enterText(find.byType(TextField), 'bench');
      await tester.pumpAndSettle();

      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.text('Back Squat'), findsNothing);
      expect(find.text('Push-Up'), findsNothing);
      expect(find.text('Pull-Up'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      expect(find.text('Back Squat'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('filter chips work', (tester) async {
      await pumpLibrary(tester);

      // Tap the Chest muscle filter chip.
      await tester.tap(find.widgetWithText(FilterChip, 'Chest'));
      await tester.pumpAndSettle();

      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.text('Push-Up'), findsOneWidget);
      expect(find.text('Back Squat'), findsNothing);
      expect(find.text('Pull-Up'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('tapping exercise shows detail sheet', (tester) async {
      await pumpLibrary(tester);

      // Tap on Barbell Bench Press card
      await tester.tap(find.text('Barbell Bench Press'));
      await tester.pumpAndSettle();

      // Detail sheet should appear
      expect(find.text('Barbell Bench Press'), findsWidgets); // Title + card
      expect(find.text('Lie on bench, press bar.'), findsOneWidget);
      expect(find.text('Chest'), findsWidgets);
      expect(find.text('Barbell'), findsWidgets);

      await disposeApp(tester);
    });

    testWidgets('empty state when no results', (tester) async {
      await pumpLibrary(tester);

      // Search for something that doesn't exist
      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pumpAndSettle();

      expect(find.text('No exercises found'), findsOneWidget);
      expect(
        find.text('Try adjusting your search or filters.'),
        findsOneWidget,
      );

      await disposeApp(tester);
    });
  });
}
