import 'package:fittrack/core/database/app_database.dart';
import 'package:fittrack/core/database/daos/program_dao.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/programs/domain/program_catalogue_ar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the Arabic program-catalogue tables against seed drift.
///
/// `kProgramNamesAr`/`kProgramDayNamesAr` are keyed by the ids
/// `ProgramSeeder` mints, so a seeder change that adds a program or day (or
/// renames one of these ids) would not fail to compile — it would just
/// quietly render in English. This seeds the real built-ins into a test
/// database and checks every one of them is covered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late ProgramDao programDao;

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

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        sharedPreferencesProvider.overrideWithValue(prefs),
        exerciseSeederProvider.overrideWith(_ExerciseSeederStub.new),
      ],
    );
    addTearDown(container.dispose);
    await container.read(programSeederProvider.future);
  });

  tearDown(() async {
    await database.close();
  });

  group('Arabic program catalogue', () {
    test('translates every built-in program', () async {
      final programs = await programDao.watchPrograms().first;
      final ids = programs.where((p) => p.isBuiltIn).map((p) => p.id).toSet();
      expect(ids, isNotEmpty);
      expect(kProgramNamesAr.keys.toSet(), ids);
    });

    test('translates every built-in program day', () async {
      final programs = await programDao.watchPrograms().first;
      final Set<String> templateIds = {};
      for (final program in programs.where((p) => p.isBuiltIn)) {
        final detail = await programDao.getDetail(program.id);
        for (final day in detail!.days) {
          templateIds.add(day.templateId);
        }
      }
      expect(templateIds, isNotEmpty);
      expect(kProgramDayNamesAr.keys.toSet(), templateIds);
    });

    test('has no blank translations', () {
      for (final MapEntry<String, String> entry in <MapEntry<String, String>>[
        ...kProgramNamesAr.entries,
        ...kProgramDayNamesAr.entries,
      ]) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
    });

    test('leaves no name still in Latin script', () {
      final RegExp latin = RegExp(r'[a-zA-Z]');
      for (final MapEntry<String, String> entry in <MapEntry<String, String>>[
        ...kProgramNamesAr.entries,
        ...kProgramDayNamesAr.entries,
      ]) {
        expect(latin.hasMatch(entry.value), isFalse, reason: entry.key);
      }
    });
  });
}

/// Stands in for the real exercise seeder, which loads a JSON asset.
class _ExerciseSeederStub extends ExerciseSeeder {
  @override
  Future<void> build() async {}
}
