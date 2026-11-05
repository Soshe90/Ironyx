import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow, Value;
import 'package:excel/excel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ironyx/core/database/app_database.dart';
import 'package:ironyx/core/database/daos/exercise_dao.dart';
import 'package:ironyx/core/formatters/unit_formatters.dart';
import 'package:ironyx/core/providers.dart';
import 'package:ironyx/core/services/program_import_service.dart';
import 'package:ironyx/core/services/workout_xlsx_import_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every exercise in the Intermediate 3-, 4- and 5-day programme workbooks,
/// as the workbooks name it, and the catalogue exercise it has to land on.
///
/// Before seed 18, 19 of these were unknown to the workout importer, which
/// turned each into a bare custom exercise with no muscles or equipment: a
/// "Barbell Deadlift" beside Deadlift, a "Hammer Curls" beside Hammer Curl.
const Map<String, String> _programmeNames = <String, String>{
  'Flat Dumbbell Press': 'Dumbbell Bench Press',
  'Barbell Romanian Deadlift': 'Romanian Deadlift',
  'Lat Pulldown': 'Lat Pulldown',
  'Bulgarian Split Squat (quad focus)': 'Bulgarian Split Squat',
  'Bulgarian Split Squat (glute focus)': 'Bulgarian Split Squat',
  'Standing Mid-Chest Cable Fly': 'Cable Fly',
  'Seated Mid-Chest Cable Fly': 'Cable Fly',
  'Standing High To Low Cable Fly': 'Cable Fly',
  'Dumbbell Lateral Raise': 'Lateral Raise',
  'Leg Press Calf Raise': 'Calf Press On The Leg Press Machine',
  'Standing Face Pulls': 'Face Pull',
  'Barbell Bench Press': 'Barbell Bench Press',
  'Standing Barbell Overhead Press': 'Overhead Press',
  'Dumbbell Fly': 'Dumbbell Flyes',
  'Barbell Row (mid/upper back)': 'Barbell Row',
  'Barbell Row (lat focus)': 'Barbell Row',
  'Behind Body Cable Curls': 'Behind-the-Body Cable Curl',
  'Lean In Lateral Raise': 'Lean-In Lateral Raise',
  'Quad-Focused Leg Press': 'Leg Press',
  'Seated Leg Extensions': 'Leg Extension',
  'Standing Weighted Calf Raise': 'Calf Raise',
  'Side Plank': 'Side Plank',
  'Low Incline Dumbbell Press': 'Incline Dumbbell Press',
  'Rear Delt Cable Row': 'Cable Rear-Delt Row',
  'Hammer Curls': 'Hammer Curl',
  'Overhead Rope Extensions': 'Overhead Tricep Extension',
  'Barbell Deadlift': 'Deadlift',
  'Hyperextensions (glute focus)': 'Back Extension',
  'Lying Leg Curls': 'Leg Curl',
  'Banded Hip Abductions': 'Banded Hip Abduction',
  'Seated Weighted Calf Raise': 'Seated Calf Raise',
  'Chest Supported Machine Row': 'Leverage Iso Row',
  'Standing Dumbbell Shoulder Press': 'Standing Dumbbell Press',
  'Cable Lateral Raise': 'Cable Lateral Raise',
  'Barbell Back Squat': 'Back Squat',
  'Dumbbell Romanian Deadlift': 'Dumbbell Romanian Deadlift',
  'Cable Pushdowns*': 'Tricep Pushdown',
  '(Weighted) Pull-Ups': 'Weighted Pull-Up',
  'Lat Focused Cable Row': 'Seated Cable Row',
  'Incline Dumbbell Curls': 'Incline Dumbbell Curl',
};

/// The three exercises written for Ironyx in seed 18.
const Set<String> _originals = <String>{
  'Behind-the-Body Cable Curl',
  'Lean-In Lateral Raise',
  'Banded Hip Abduction',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeExerciseName', () {
    test('ignores case, punctuation and spacing', () {
      expect(normalizeExerciseName('Cable Pushdowns*'), 'cable pushdowns');
      expect(normalizeExerciseName('  Push-Ups '), 'push ups');
      expect(
        normalizeExerciseName('Barbell Row (mid/upper back)'),
        'barbell row mid upper back',
      );
      expect(normalizeExerciseName('(Weighted) Pull-Ups'), 'weighted pull ups');
    });

    test('keeps a name with no Latin letters or digits as it is', () {
      // It used to normalize to '', and '' matched every other such name.
      expect(normalizeExerciseName(' دفع الحديد '), 'دفع الحديد');
      expect(
        normalizeExerciseName('دفع الحديد'),
        isNot(normalizeExerciseName('سحب')),
      );
    });
  });

  group('the bundled catalogue', () {
    late List<Map<String, dynamic>> exercises;

    setUpAll(() {
      final Map<String, dynamic> seed = jsonDecode(
        File('assets/data/exercises_seed.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      exercises = <Map<String, dynamic>>[
        for (final dynamic e in seed['exercises'] as List<dynamic>)
          e as Map<String, dynamic>,
      ];
    });

    test('no two exercises share a name or alias once normalized', () {
      // The builder refuses such a catalogue; this catches a hand edit.
      final Map<String, String> owner = <String, String>{};
      for (final Map<String, dynamic> e in exercises) {
        final String name = e['name'] as String;
        for (final String label in <String>[
          name,
          ...(e['aliases'] as List<dynamic>).cast<String>(),
        ]) {
          final String key = normalizeExerciseName(label);
          final String other = owner.putIfAbsent(key, () => name);
          expect(other, name, reason: '"$label" also names "$other"');
        }
      }
    });

    test('the exercises written for Ironyx say so and ship no images', () {
      for (final String name in _originals) {
        final Map<String, dynamic> e =
            exercises.singleWhere((x) => x['name'] == name);
        final Map<String, dynamic> source =
            (e['sources'] as List<dynamic>).cast<Map<String, dynamic>>().single;
        expect(source['sourceName'], 'ironyx', reason: name);
        expect(source['license'], isNotEmpty, reason: name);
        expect(
          (e['media'] as List<dynamic>)
              .cast<Map<String, dynamic>>()
              .where((Map<String, dynamic> m) => m['type'] == 'image'),
          isEmpty,
          reason: name,
        );
        expect(e['instructions'], isNotEmpty, reason: name);
        expect(e['muscles'], isNotEmpty, reason: name);
        expect(e['equipment'], isNotEmpty, reason: name);
      }
    });
  });

  group('with the real catalogue seeded', () {
    late AppDatabase database;
    late Map<String, String> idByName;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      database = AppDatabase.forTesting();
      final ProviderContainer container = ProviderContainer(
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
      final List<QueryRow> rows = await database
          .customSelect('SELECT id, name FROM exercises_table')
          .get();
      idByName = <String, String>{
        for (final QueryRow r in rows)
          r.read<String>('name'): r.read<String>('id'),
      };
    });

    test('every programme name resolves to its catalogue exercise', () async {
      final Map<String, String> lookup =
          await ExerciseDao(database).exerciseIdsByLookupName();

      for (final MapEntry<String, String> entry in _programmeNames.entries) {
        expect(
          lookup[normalizeExerciseName(entry.key)],
          idByName[entry.value],
          reason: '"${entry.key}" should be "${entry.value}"',
        );
      }
    });

    test('importing all of them creates no custom exercise', () async {
      // One workbook, one session, every programme exercise with one set.
      final Excel excel = Excel.createExcel();
      final Sheet sheet = excel[excel.getDefaultSheet()!];
      const int groupStart = 3;
      sheet
          .cell(
            CellIndex.indexByColumnRow(columnIndex: groupStart, rowIndex: 0),
          )
          .value = const DateCellValue(year: 2026, month: 10, day: 1);
      int row = 2;
      for (final String name in _programmeNames.keys) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = TextCellValue(name);
        sheet
            .cell(
              CellIndex.indexByColumnRow(
                columnIndex: groupStart,
                rowIndex: row + 1,
              ),
            )
            .value = const IntCellValue(8);
        sheet
            .cell(
              CellIndex.indexByColumnRow(
                columnIndex: groupStart + 1,
                rowIndex: row + 1,
              ),
            )
            .value = const DoubleCellValue(40);
        row += 2;
      }

      const WorkoutXlsxImportService service = WorkoutXlsxImportService();
      final WorkoutXlsxImportResult result = await service.parse(
        excel.encode()!,
        database,
        sourceUnit: WeightUnit.kg,
      );
      expect(result.unknownExercises, isEmpty);

      final int before = (await database
              .customSelect('SELECT COUNT(*) AS n FROM exercises_table')
              .getSingle())
          .read<int>('n');
      await service.apply(database, result);
      final int after = (await database
              .customSelect('SELECT COUNT(*) AS n FROM exercises_table')
              .getSingle())
          .read<int>('n');
      expect(after, before, reason: 'no custom exercise was created');

      final List<String> logged = (await database
              .customSelect(
                'SELECT e.name AS name FROM workout_exercises_table we '
                'JOIN exercises_table e ON e.id = we.exercise_id '
                'ORDER BY we.order_index',
              )
              .get())
          .map((QueryRow r) => r.read<String>('name'))
          .toList();
      expect(logged, _programmeNames.values.toList());
    });

    test('a programme CSV written with coaching names imports', () async {
      const String csv = 'program,day,exercise,sets,reps\n'
          'Intermediate,Upper 1,Barbell Bench Press,3,8-10\n'
          'Intermediate,Upper 1,Flat Dumbbell Press,3,8-10\n'
          'Intermediate,Upper 1,Cable Pushdowns*,3,10-12\n'
          'Intermediate,Lower 2,Banded Hip Abductions,2,20\n'
          'Intermediate,Lower 2,Something Else Entirely,2,10\n';

      const ProgramImportService service = ProgramImportService();
      final result = await service.parse(csv, database);

      expect(result.unknownExercises, <String>['Something Else Entirely']);
      final List<String> ids = <String>[
        for (final program in result.programs)
          for (final day in program.days)
            for (final exercise in day.exercises) exercise.exerciseId,
      ];
      expect(ids, <String?>[
        idByName['Barbell Bench Press'],
        idByName['Dumbbell Bench Press'],
        idByName['Tricep Pushdown'],
        idByName['Banded Hip Abduction'],
      ]);
    });

    test('the new exercises are found by Library search', () async {
      final ExerciseDao dao = ExerciseDao(database);
      Future<List<String>> search(String q) async =>
          (await dao.searchByName(q).first)
              .map((s) => s.exercise.name)
              .toList();

      expect(await search('bayesian'), contains('Behind-the-Body Cable Curl'));
      expect(await search('lean-in'), contains('Lean-In Lateral Raise'));
      expect(await search('hip abduction'), contains('Banded Hip Abduction'));
      // And a programme name finds the exercise it is another name for.
      expect(await search('flat dumbbell'), contains('Dumbbell Bench Press'));
    });
  });

  group('exerciseIdsByLookupName priority', () {
    late AppDatabase database;
    late ExerciseDao dao;

    setUp(() async {
      database = AppDatabase.forTesting();
      dao = ExerciseDao(database);
      addTearDown(database.close);
      ExercisesTableCompanion exercise(
        String id,
        String name, {
        bool custom = false,
      }) =>
          ExercisesTableCompanion.insert(
            id: id,
            slug: id,
            name: name,
            category: 'strength',
            difficulty: 'intermediate',
            movementPattern: 'other',
            seedVersion: custom ? 0 : 1,
            isCustom: Value(custom),
          );
      await dao.upsertExercises([
        exercise('hammer', 'Hammer Curl'),
        exercise('curl', 'Dumbbell Curl'),
        // What an import before seed 18 left behind.
        exercise('old-import', 'Hammer Curls', custom: true),
        exercise('arabic', 'دفع الحديد', custom: true),
      ]);
      await dao.replaceAliases('hammer', [
        ExerciseAliasesTableCompanion.insert(
          id: 'a1',
          exerciseId: 'hammer',
          alias: 'Hammer Curls',
        ),
      ]);
      await dao.replaceAliases('curl', [
        // An alias equal to another exercise's name.
        ExerciseAliasesTableCompanion.insert(
          id: 'a2',
          exerciseId: 'curl',
          alias: 'hammer-curl',
        ),
      ]);
    });

    test('a catalogue alias wins over a custom exercise of that name',
        () async {
      final Map<String, String> lookup = await dao.exerciseIdsByLookupName();
      expect(lookup['hammer curls'], 'hammer');
    });

    test('a catalogue name wins over another exercise\'s alias', () async {
      final Map<String, String> lookup = await dao.exerciseIdsByLookupName();
      expect(lookup['hammer curl'], 'hammer');
    });

    test('a custom exercise is still found by its own name', () async {
      final Map<String, String> lookup = await dao.exerciseIdsByLookupName();
      expect(lookup['دفع الحديد'], 'arabic');
      // Another non-Latin name does not match it.
      expect(lookup[normalizeExerciseName('سحب')], isNull);
    });

    test('an alias on a custom exercise is not used', () async {
      await dao.replaceAliases('old-import', [
        ExerciseAliasesTableCompanion.insert(
          id: 'a3',
          exerciseId: 'old-import',
          alias: 'Curl Thing',
        ),
      ]);
      final Map<String, String> lookup = await dao.exerciseIdsByLookupName();
      expect(lookup.containsKey('curl thing'), isFalse);
    });
  });
}
