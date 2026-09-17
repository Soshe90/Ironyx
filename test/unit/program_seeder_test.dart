import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/program_dao.dart';
import 'package:ironyx/core/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ProgramDao programDao;

  Future<ProviderContainer> containerWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(prefs),
        // The catalogue is seeded by hand below; the real seeder reads an
        // asset bundle this test has no reason to exercise.
        exerciseSeederProvider.overrideWith(ExerciseSeederStub.new),
      ],
    );
  }

  setUp(() async {
    database = AppDatabase.forTesting();
    programDao = ProgramDao(database);
    await database.batch((b) {
      b.insertAll(database.exercisesTable, [
        for (var i = 1; i <= 40; i++)
          ExercisesTableCompanion.insert(
            id: 'ex_${i.toString().padLeft(3, '0')}',
            slug: 'ex-$i',
            name: 'Exercise $i',
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'horizontalPush',
            seedVersion: 1,
          ),
      ]);
    });
  });

  tearDown(() async {
    await database.close();
  });

  test('seeds the three built-in programs on a fresh install', () async {
    final container = await containerWith(<String, Object>{});
    addTearDown(container.dispose);

    await container.read(programSeederProvider.future);

    expect(
      await programDao.allProgramNames(),
      {'Full Body', 'Upper / Lower', 'Push / Pull / Legs'},
    );
  });

  test(
      're-seeding skips a built-in whose name a user-edited program now owns, '
      'instead of failing on the UNIQUE name constraint', () async {
    final first = await containerWith(<String, Object>{});
    await first.read(programSeederProvider.future);
    first.dispose();

    // Simulate the user editing "Full Body": the program keeps its name but
    // is no longer built-in, so `deleteBuiltInPrograms` leaves it alone.
    await (database.update(database.programsTable)
          ..where((t) => t.id.equals('builtin_full_body')))
        .write(const ProgramsTableCompanion(isBuiltIn: Value(false)));

    // A later seed-version bump: the marker is behind, so the seeder reruns.
    final second = await containerWith(<String, Object>{});
    addTearDown(second.dispose);
    await second.read(programSeederProvider.future);

    final surviving = await programDao.getDetail('builtin_full_body');
    expect(surviving, isNotNull);
    expect(surviving!.program.isBuiltIn, isFalse);
    expect(
      (await programDao.watchPrograms().first)
          .where((p) => p.name == 'Full Body'),
      hasLength(1),
    );
    // The other two were re-seeded normally.
    expect(
      await programDao.allProgramNames(),
      {'Full Body', 'Upper / Lower', 'Push / Pull / Legs'},
    );
  });
}

/// Stands in for the real exercise seeder, which loads a JSON asset.
class ExerciseSeederStub extends ExerciseSeeder {
  @override
  Future<void> build() async {}
}
