import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/database/database_providers.dart';
import 'package:ironyx/core/database/tables/exercises.dart';
import 'package:ironyx/core/database/tables/muscles.dart';
import 'package:ironyx/features/library/presentation/exercise_search.dart';
import 'package:ironyx/l10n/app_localizations.dart';

/// The search shared by the Library page and the exercise picker.
void main() {
  group('exerciseSource', () {
    test('nothing to narrow by is the whole catalogue', () {
      expect(exerciseSource(query: ''), allExercisesStreamProvider);
    });

    test('an Arabic search is not sent to SQL', () {
      expect(exerciseSource(query: 'ضغط'), allExercisesStreamProvider);
      expect(
        exerciseSource(query: 'ضغط', muscleId: 'chest'),
        exercisesFilteredStreamProvider(muscleId: 'chest'),
      );
    });

    test('a Latin search and the filters are one query', () {
      expect(
        exerciseSource(
          query: 'bench',
          muscleId: 'chest',
          pattern: MovementPattern.horizontalPush,
        ),
        exercisesFilteredStreamProvider(
          query: 'bench',
          muscleId: 'chest',
          pattern: MovementPattern.horizontalPush,
        ),
      );
    });
  });

  testWidgets('the detail line: muscle, equipment, then pattern if asked',
      (tester) async {
    final ExerciseSummary summary = ExerciseSummary(
      exercise: Exercise(
        id: 'bench',
        slug: 'bench',
        name: 'Bench Press',
        description: '',
        category: ExerciseCategory.strength,
        difficulty: Difficulty.intermediate,
        movementPattern: MovementPattern.horizontalPush,
        isUnilateral: false,
        isBodyweight: false,
        isTimeBased: false,
        seedVersion: 1,
        isCustom: false,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
      ),
      primaryMuscle: const Muscle(
        id: 'chest',
        name: 'chest',
        displayName: 'Chest',
      ),
      equipmentNames: const <String>['Barbell'],
      equipmentIds: const <String>['barbell'],
      media: null,
      fallbackMedia: null,
    );
    late String full;
    late String short;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (BuildContext context) {
            full = exerciseDetailLine(context, summary);
            short = exerciseDetailLine(context, summary, withPattern: false);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(full, startsWith('Chest · Barbell · '));
    expect(short, 'Chest · Barbell');
  });
}
