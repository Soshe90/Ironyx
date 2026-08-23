import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/exercise_dao.dart';
import 'package:fittrack/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seeds every exercise from the bundled asset', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final database = AppDatabase.forTesting();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );

    addTearDown(() async {
      container.dispose();
      await database.close();
    });

    await container.read(exerciseSeederProvider.future);
    final exercises = await ExerciseDao(database).watchAll().first;

    expect(exercises, hasLength(86));
    expect(
      exercises.map((summary) => summary.exercise.name),
      containsAll(<String>[
        'Dumbbell Romanian Deadlift',
        'Cable Incline Fly',
        'Cable Seated Chest Fly',
        'Cable Fly with Chest Supported',
        'Cable Standing Fly',
        'Cable Lying Fly',
        'Cable Low Fly',
        'Cable Middle Fly',
      ]),
    );
  });
}
