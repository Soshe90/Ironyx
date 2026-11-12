import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/equipment_dao.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/daos/muscle_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/theme/app_spacing.dart';
import 'package:ironyx/core/widgets/app_card.dart';

import '../helpers/pump_app.dart';
import '../helpers/stub_seeders.dart';

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

    Future<void> pumpLibrary(
      WidgetTester tester, {
      String? locale,
      List<dynamic> overrides = const <dynamic>[],
    }) =>
        pumpApp(
          tester,
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            ...stubSeeders(),
            ...overrides,
          ],
          initialLocation: '/library',
          prefs: <String, Object>{
            ...seededPrefs,
            if (locale != null) 'app_locale': locale,
          },
          surfaceSize: surface,
          // This screen is entirely Drift-stream driven.
          awaitDatabase: true,
        );

    testWidgets('displays exercise list', (tester) async {
      await pumpLibrary(tester);

      expect(find.text('Exercise library'), findsOneWidget);
      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.text('Back Squat'), findsOneWidget);
      expect(find.text('Push-Up'), findsOneWidget);
      expect(find.text('Pull-Up'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('an Arabic search finds exercises by their Arabic name',
        (tester) async {
      // A slug the Arabic catalogue knows: "ضغط بار على مقعد مستوٍ".
      await ExerciseDao(database).upsertExercises([
        ExercisesTableCompanion.insert(
          id: 'barbell-bench-press',
          slug: 'barbell-bench-press',
          name: 'Barbell Bench Press (catalogue)',
          category: 'strength',
          difficulty: 'intermediate',
          movementPattern: 'horizontalPush',
          seedVersion: 1,
        ),
      ]);
      await pumpLibrary(tester, locale: 'ar');

      // Without diacritics, with a plain alef: as a keyboard types it.
      await tester.enterText(find.byType(TextField), 'ضغط بار مستو');
      await tester.pump(AppDuration.inputDebounce);
      await tester.pumpAndSettle();

      expect(find.text('ضغط بار على مقعد مستوٍ'), findsOneWidget);
      // The others have no Arabic name and do not match.
      expect(find.text('Back Squat'), findsNothing);
      expect(find.text('Push-Up'), findsNothing);

      // Something no name holds: nothing, and the empty state.
      await tester.enterText(find.byType(TextField), 'سباحة');
      await tester.pump(AppDuration.inputDebounce);
      await tester.pumpAndSettle();
      expect(find.text('ضغط بار على مقعد مستوٍ'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('search filters exercises', (tester) async {
      await pumpLibrary(tester);

      // Search for "bench". Search is debounced, and a pending Timer is not
      // an animation, so pumpAndSettle alone would return before it fires.
      await tester.enterText(find.byType(TextField), 'bench');
      await tester.pump(AppDuration.inputDebounce);
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

      // Filters collapse to one chip per dimension; open Muscle and pick
      // Chest from its menu.
      await tester.tap(find.text('Muscle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chest').last);
      await tester.pumpAndSettle();

      expect(find.text('Barbell Bench Press'), findsOneWidget);
      expect(find.text('Push-Up'), findsOneWidget);
      expect(find.text('Back Squat'), findsNothing);
      expect(find.text('Pull-Up'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('in Arabic the list is in the order of the Arabic names',
        (tester) async {
      // English order: Back Squat, Pull-Up, Push-Up. Arabic: سكوات خلفي,
      // العقلة, تمرين الضغط, which sort as ا, ت, س.
      for (final (String slug, String name) in <(String, String)>[
        ('back-squat', 'Back Squat (catalogue)'),
        ('pull-up', 'Pull-Up (catalogue)'),
        ('push-up', 'Push-Up (catalogue)'),
      ]) {
        await ExerciseDao(database).upsertExercises([
          ExercisesTableCompanion.insert(
            id: slug,
            slug: slug,
            name: name,
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'horizontalPush',
            seedVersion: 1,
          ),
        ]);
      }
      await pumpLibrary(tester, locale: 'ar');

      double top(String text) => tester.getTopLeft(find.text(text)).dy;
      expect(top('العقلة'), lessThan(top('تمرين الضغط')));
      expect(top('تمرين الضغط'), lessThan(top('سكوات خلفي')),
          reason: 'by the English names, سكوات خلفي came first');

      await disposeApp(tester);
    });

    testWidgets('a row shows its equipment icon', (tester) async {
      await pumpLibrary(tester);

      // Push-Up is bodyweight; its name was looked up as an icon id and
      // always fell through to the generic "more" icon.
      final Finder pushUp = find.ancestor(
        of: find.text('Push-Up'),
        matching: find.byType(AppCard),
      );
      expect(
        find.descendant(
            of: pushUp, matching: find.byIcon(Icons.accessibility_new)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.more_horiz), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('in Arabic equipment is translated, in rows and the filter',
        (tester) async {
      await pumpLibrary(tester, locale: 'ar');

      // Back Squat: legs, barbell. "بار" is barbell in Arabic.
      // The detail line under a name is "muscle · equipment · pattern".
      expect(find.textContaining(' · بار · '), findsWidgets);
      expect(find.textContaining(' · Barbell'), findsNothing,
          reason: 'equipment was looked up by name and stayed English');
      expect(find.textContaining('Bodyweight'), findsNothing);

      await tester.tap(find.text('المعدّات'));
      await tester.pumpAndSettle();
      expect(find.text('وزن الجسم'), findsWidgets);
      expect(find.text('Bodyweight'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('Retry reloads the search that failed', (tester) async {
      int tries = 0;
      await pumpLibrary(
        tester,
        overrides: [
          exercisesFilteredStreamProvider(query: 'boom').overrideWith((ref) {
            tries++;
            return Stream<List<ExerciseSummary>>.error(Exception('boom'));
          }),
        ],
      );
      await tester.enterText(find.byType(TextField), 'boom');
      await tester.pump(AppDuration.inputDebounce);
      // Riverpod retries a failure before showing it (about 38 s).
      for (int i = 0; i < 45; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('Try again'), findsOneWidget);

      final int before = tries;
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(tries, greaterThan(before),
          reason: 'Retry reloaded the full list, not the failed search');

      await disposeApp(tester);
    });

    test('a search no longer shown is released', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          ...stubSeeders().cast(),
        ],
      );
      addTearDown(container.dispose);
      final provider = exercisesFilteredStreamProvider(query: 'squat');
      final sub = container.listen(provider, (_, __) {});
      expect(container.exists(provider), isTrue);

      sub.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.exists(provider), isFalse,
          reason: 'kept alive, every search stayed a live query');
    });

    testWidgets("an active chip's × clears its filter", (tester) async {
      await pumpLibrary(tester);
      await tester.tap(find.text('Muscle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chest').last);
      await tester.pumpAndSettle();
      expect(find.text('Back Squat'), findsNothing);

      await tester.tap(find.byTooltip('Clear Muscle filter'));
      await tester.pumpAndSettle();

      // No menu opened, and the filter is gone.
      expect(find.text('All Muscle'), findsNothing);
      expect(find.byType(PopupMenuItem<Object?>), findsNothing);
      expect(find.text('Back Squat'), findsOneWidget);
      expect(find.text('Muscle'), findsOneWidget);

      await disposeApp(tester);
    });

    testWidgets('a search keeps the filters chosen', (tester) async {
      await pumpLibrary(tester);

      await tester.tap(find.text('Muscle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chest').last);
      await tester.pumpAndSettle();
      // "pu" is in Push-Up and Pull-Up; only Push-Up is chest.
      await tester.enterText(find.byType(TextField), 'pu');
      await tester.pump(AppDuration.inputDebounce);
      await tester.pumpAndSettle();

      expect(find.text('Push-Up'), findsOneWidget);
      expect(find.text('Pull-Up'), findsNothing,
          reason: 'the search used to drop the muscle filter');
      expect(find.text('Barbell Bench Press'), findsNothing);

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

    testWidgets('lists join with the English comma in English', (tester) async {
      // The Arabic comma used to be hardcoded for every language, so an
      // English card read "Barbell، Bodyweight" (seen on a real device).
      await ExerciseDao(database).replaceEquipmentLinks('bench_1', [
        for (final String eq in <String>['barbell', 'bodyweight'])
          ExerciseEquipmentTableCompanion.insert(
            id: 'bench_1_$eq',
            exerciseId: 'bench_1',
            equipmentId: eq,
          ),
      ]);
      await pumpLibrary(tester);

      expect(find.textContaining('Barbell, Bodyweight'), findsOneWidget);
      expect(find.textContaining('،'), findsNothing);

      await disposeApp(tester);
    });

    testWidgets('empty state when no results', (tester) async {
      await pumpLibrary(tester);

      // Search for something that doesn't exist
      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pump(AppDuration.inputDebounce);
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
